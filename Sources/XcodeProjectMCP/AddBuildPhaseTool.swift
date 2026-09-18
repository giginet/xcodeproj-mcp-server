import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct AddBuildPhaseTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "add_build_phase",
            description:
                "Add custom build phases",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to add build phase to"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the build phase"),
                    ]),
                    "phase_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of build phase (run_script, copy_files)"),
                    ]),
                    "script": .object([
                        "type": .string("string"),
                        "description": .string("Script content (for run_script phase)"),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Destination for copy files phase (resources, frameworks, executables, plugins, shared_support)"
                        ),
                    ]),
                    "files": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Array of file paths to copy (for copy_files phase)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                    .string("phase_type"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(phaseName) = arguments["phase_name"],
            case let .string(phaseType) = arguments["phase_type"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, phase_name, and phase_type are required")
        }

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            switch loadedProject {
            case .xcproj(var file):
                guard file.project.targets.contains(where: { $0.name == targetName }) else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }

                let newPhase: XCSchema.BuildPhase
                let phaseObjectID = XCProjSupport.makeObjectID()
                switch phaseType.lowercased() {
                case "run_script":
                    guard case let .string(script) = arguments["script"] else {
                        throw MCPError.invalidParams("script is required for run_script phase")
                    }
                    newPhase = .script(
                        XCSchema.ScriptBuildPhaseProperties(
                            objectID: phaseObjectID,
                            name: phaseName,
                            shellPath: "/bin/sh",
                            script: script,
                            logEnvironmentVariables: false,
                            inputPaths: [],
                            inputFileListPaths: [],
                            outputPaths: [],
                            outputFileListPaths: [],
                            dependencyFile: nil,
                            runOnEveryBuild: false,
                            scope: .always))
                case "copy_files":
                    guard case let .string(destination) = arguments["destination"] else {
                        throw MCPError.invalidParams(
                            "destination is required for copy_files phase")
                    }
                    let bundleBasePath: XCSchema.BundleBasePath
                    switch destination.lowercased() {
                    case "resources":
                        bundleBasePath = .resourcesDir
                    case "frameworks":
                        bundleBasePath = .frameworksDir
                    case "executables":
                        bundleBasePath = .executablesDir
                    case "plugins":
                        bundleBasePath = .plugInsDir
                    case "shared_support":
                        bundleBasePath = .sharedSupportDir
                    default:
                        throw MCPError.invalidParams(
                            "Invalid destination: \(destination). Must be one of: resources, frameworks, executables, plugins, shared_support"
                        )
                    }
                    newPhase = .copy(
                        XCSchema.CopyFilesBuildPhaseProperties(
                            objectID: phaseObjectID,
                            name: phaseName,
                            bundleBasePath: bundleBasePath,
                            relativePath: "",
                            scope: .always))
                default:
                    throw MCPError.invalidParams(
                        "Invalid phase_type: \(phaseType). Must be one of: run_script, copy_files"
                    )
                }

                XCProjSupport.modifyTarget(named: targetName, in: &file.project) { properties in
                    properties.buildPhases.append(newPhase)
                }

                // Map listed files into the new copy phase by its object ID
                if phaseType.lowercased() == "copy_files",
                    case let .array(filesArray) = arguments["files"]
                {
                    for fileValue in filesArray {
                        guard case let .string(filePath) = fileValue else { continue }
                        let resolvedFilePath = try pathUtility.resolvePath(from: filePath)
                        let relativePath =
                            pathUtility.makeRelativePath(from: resolvedFilePath)
                            ?? resolvedFilePath
                        let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
                        XCProjTreeEditor.updateFirstFileReference(
                            in: &file.project.topLevelReferences,
                            where: { fileReference in
                                let storedPath = fileReference.path.stringRepresentation
                                let storedName =
                                    storedPath.split(separator: "/").last.map(String.init)
                                    ?? storedPath
                                return storedPath == relativePath || storedPath == filePath
                                    || storedName == fileName
                            },
                            update: { fileReference, _ in
                                fileReference.buildFiles.append(
                                    XCSchema.ProjectBuildFile(
                                        objectID: nil,
                                        buildPhase: .objectID(phaseObjectID),
                                        properties: XCProjSupport.emptyBuildFileProperties()))
                            })
                    }
                }

                try file.save()

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully added \(phaseType) build phase '\(phaseName)' to target '\(targetName)'"
                        )
                    ]
                )
            case .pbxproj(let xcodeproj):
                // Find the target
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }

                switch phaseType.lowercased() {
                case "run_script":
                    guard case let .string(script) = arguments["script"] else {
                        throw MCPError.invalidParams("script is required for run_script phase")
                    }

                    // Create shell script build phase
                    let shellScriptPhase = PBXShellScriptBuildPhase(
                        name: phaseName,
                        shellScript: script
                    )
                    xcodeproj.pbxproj.add(object: shellScriptPhase)
                    target.buildPhases.append(shellScriptPhase)

                case "copy_files":
                    guard case let .string(destination) = arguments["destination"] else {
                        throw MCPError.invalidParams("destination is required for copy_files phase")
                    }

                    // Map destination string to enum
                    let dstSubfolderSpec: PBXCopyFilesBuildPhase.SubFolder
                    switch destination.lowercased() {
                    case "resources":
                        dstSubfolderSpec = .resources
                    case "frameworks":
                        dstSubfolderSpec = .frameworks
                    case "executables":
                        dstSubfolderSpec = .executables
                    case "plugins":
                        dstSubfolderSpec = .plugins
                    case "shared_support":
                        dstSubfolderSpec = .sharedSupport
                    default:
                        throw MCPError.invalidParams(
                            "Invalid destination: \(destination). Must be one of: resources, frameworks, executables, plugins, shared_support"
                        )
                    }

                    // Create copy files build phase
                    let copyFilesPhase = PBXCopyFilesBuildPhase(
                        dstPath: "",
                        dstSubfolderSpec: dstSubfolderSpec,
                        name: phaseName
                    )
                    xcodeproj.pbxproj.add(object: copyFilesPhase)

                    // Add files if provided
                    if case let .array(filesArray) = arguments["files"] {
                        for fileValue in filesArray {
                            guard case let .string(filePath) = fileValue else { continue }

                            // Resolve and validate the file path
                            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)
                            let relativePath =
                                pathUtility.makeRelativePath(from: resolvedFilePath)
                                ?? resolvedFilePath

                            // Find file reference
                            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
                            if let fileRef = xcodeproj.pbxproj.fileReferences.first(where: {
                                $0.path == relativePath || $0.path == filePath
                                    || $0.name == fileName
                            }) {
                                let buildFile = PBXBuildFile(file: fileRef)
                                xcodeproj.pbxproj.add(object: buildFile)
                                copyFilesPhase.files?.append(buildFile)
                            }
                        }
                    }

                    target.buildPhases.append(copyFilesPhase)

                default:
                    throw MCPError.invalidParams(
                        "Invalid phase_type: \(phaseType). Must be one of: run_script, copy_files")
                }

                // Save project
                try xcodeproj.write(path: Path(projectURL.path))

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully added \(phaseType) build phase '\(phaseName)' to target '\(targetName)'"
                        )
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to add build phase to Xcode project: \(error.descriptiveMessage)")
        }
    }
}
