import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct AddFrameworkTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "add_framework",
            description:
                "Add framework dependencies",
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
                        "description": .string("Name of the target to add framework to"),
                    ]),
                    "framework_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the framework to add (e.g., UIKit, Foundation, or path to custom framework)"
                        ),
                    ]),
                    "embed": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to embed the framework (for custom frameworks, optional, defaults to false)"
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("framework_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(frameworkName) = arguments["framework_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and framework_name are required")
        }

        let embed: Bool
        if case let .bool(shouldEmbed) = arguments["embed"] {
            embed = shouldEmbed
        } else {
            embed = false
        }

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            // Determine if this is a system framework or custom framework
            let isSystemFramework =
                !frameworkName.contains("/") && !frameworkName.hasSuffix(".framework")

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                if let earlyResult = try addToPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL, targetName: targetName,
                    frameworkName: frameworkName, isSystemFramework: isSystemFramework,
                    embed: embed)
                {
                    return earlyResult
                }
            case .xcproj(var file):
                guard file.project.targets.contains(where: { $0.name == targetName }) else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }

                let frameworkFileName: String
                let frameworkPath: XCSchema.FilePath
                if isSystemFramework {
                    frameworkFileName = "\(frameworkName).framework"
                    frameworkPath = try XCSchema.FilePath(
                        base: .sdk, path: "System/Library/Frameworks/\(frameworkFileName)")
                } else {
                    let resolvedFrameworkPath = try pathUtility.resolvePath(from: frameworkName)
                    frameworkFileName =
                        URL(fileURLWithPath: resolvedFrameworkPath)
                        .lastPathComponent
                    let relativePath =
                        pathUtility.makeRelativePath(from: resolvedFrameworkPath)
                        ?? resolvedFrameworkPath
                    frameworkPath = try XCSchema.FilePath(base: .group, path: relativePath)
                }

                // Check if the framework is already linked into the target
                var frameworkExists = false
                XCProjTreeEditor.forEachFileReference(in: file.project.topLevelReferences) {
                    fileReference in
                    let storedPath = fileReference.path.stringRepresentation
                    let storedName =
                        storedPath.split(separator: "/").last.map(String.init) ?? storedPath
                    guard storedName == frameworkFileName else { return }
                    let linked = fileReference.buildFiles.contains { buildFile in
                        XCProjSupport.buildFile(
                            buildFile, belongsTo: targetName, phaseIDs: [],
                            kinds: [.frameworks])
                    }
                    if linked { frameworkExists = true }
                }
                if frameworkExists {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Framework '\(frameworkName)' already exists in target '\(targetName)'"
                            )
                        ]
                    )
                }

                // Ensure the target has the phases the membership entries reference
                let embedPhaseName = "Embed Frameworks"
                XCProjSupport.modifyTarget(named: targetName, in: &file.project) { properties in
                    XCProjSupport.ensureBuildPhase(kind: .frameworks, in: &properties)
                    if embed && !isSystemFramework {
                        let hasEmbedPhase = properties.buildPhases.contains { phase in
                            if case .copy(let copyProperties) = phase {
                                return copyProperties.bundleBasePath == .frameworksDir
                            }
                            return false
                        }
                        if !hasEmbedPhase {
                            properties.buildPhases.append(
                                .copy(
                                    XCSchema.CopyFilesBuildPhaseProperties(
                                        objectID: XCProjSupport.makeObjectID(),
                                        name: embedPhaseName,
                                        bundleBasePath: .frameworksDir,
                                        relativePath: "",
                                        scope: .always)))
                        }
                    }
                }

                var buildFiles = [
                    XCProjSupport.makeBuildFile(targetName: targetName, kind: .frameworks)
                ]
                if embed && !isSystemFramework {
                    // CodeSignOnCopy + RemoveHeadersOnCopy, as the pbxproj arm sets
                    var attributes = XCProjSupport.emptyBuildFileAttributes()
                    attributes.codeSignOnCopy = true
                    attributes.headerPreservation = .removeOnCopy
                    buildFiles.append(
                        XCProjSupport.makeBuildFile(
                            targetName: targetName, kind: .copy, phaseName: embedPhaseName,
                            properties: XCSchema.BuildFileProperties(
                                platformFilters: [],
                                additionalBuildFlags: nil,
                                assetTags: [],
                                attributes: attributes)))
                }

                let fileReference = XCSchema.FileReference(
                    objectID: nil,
                    path: frameworkPath,
                    explicitFileType: nil,
                    expectedSignature: nil,
                    textEncoding: nil,
                    lineEnding: nil,
                    includeInIndex: nil,
                    buildFiles: buildFiles
                )

                // Add to a "Frameworks" group, creating it when missing
                var frameworksGroupIndexPath = XCProjTreeEditor.findGroup(
                    named: "Frameworks", in: file.project.topLevelReferences)
                if frameworksGroupIndexPath == nil {
                    file.project.topLevelReferences.append(
                        .group(
                            XCSchema.Group(
                                objectID: nil, name: "Frameworks", path: "",
                                includeInIndex: nil, children: [])))
                    frameworksGroupIndexPath = [file.project.topLevelReferences.count - 1]
                }
                XCProjTreeEditor.append(
                    .fileReference(fileReference), toGroupAt: frameworksGroupIndexPath,
                    in: &file.project.topLevelReferences)

                try file.save()
            }

            let embedText = embed && !isSystemFramework ? " (embedded)" : ""
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added framework '\(frameworkName)' to target '\(targetName)'\(embedText)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add framework to Xcode project: \(error.localizedDescription)")
        }
    }

    /// Returns a Result only for early-exit conditions; nil on success.
    private func addToPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, targetName: String, frameworkName: String,
        isSystemFramework: Bool, embed: Bool
    ) throws -> CallTool.Result? {
        // Find the target
        guard
            let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
        else {
            return CallTool.Result(
                content: [
                    .text("Target '\(targetName)' not found in project")
                ]
            )
        }

        // Find or create frameworks build phase
        let frameworksBuildPhase: PBXFrameworksBuildPhase
        if let existingPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }
        ) as? PBXFrameworksBuildPhase {
            frameworksBuildPhase = existingPhase
        } else {
            frameworksBuildPhase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: frameworksBuildPhase)
            target.buildPhases.append(frameworksBuildPhase)
        }

        let frameworkFileName: String
        let frameworkPath: String

        if isSystemFramework {
            frameworkFileName = "\(frameworkName).framework"
            frameworkPath = "System/Library/Frameworks/\(frameworkFileName)"
        } else {
            // Resolve custom framework path
            let resolvedFrameworkPath = try pathUtility.resolvePath(from: frameworkName)
            frameworkFileName = URL(fileURLWithPath: resolvedFrameworkPath).lastPathComponent
            // Use relative path from project for file reference
            frameworkPath =
                pathUtility.makeRelativePath(from: resolvedFrameworkPath)
                ?? resolvedFrameworkPath
        }

        // Check if framework already exists
        let frameworkExists =
            frameworksBuildPhase.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == frameworkFileName || fileRef.path == frameworkName
                }
                return false
            } ?? false

        if frameworkExists {
            return CallTool.Result(
                content: [
                    .text(
                        "Framework '\(frameworkName)' already exists in target '\(targetName)'")
                ]
            )
        }

        // Create file reference for framework
        let frameworkFileRef: PBXFileReference
        if isSystemFramework {
            frameworkFileRef = PBXFileReference(
                sourceTree: .sdkRoot,
                name: frameworkFileName,
                lastKnownFileType: "wrapper.framework",
                path: frameworkPath
            )
        } else {
            frameworkFileRef = PBXFileReference(
                sourceTree: .group,
                name: frameworkFileName,
                lastKnownFileType: "wrapper.framework",
                path: frameworkPath
            )
        }
        xcodeproj.pbxproj.add(object: frameworkFileRef)

        // Add to frameworks group if exists
        if let project = xcodeproj.pbxproj.rootObject,
            let frameworksGroup = project.mainGroup?.children.first(where: { element in
                if let group = element as? PBXGroup {
                    return group.name == "Frameworks"
                }
                return false
            }) as? PBXGroup
        {
            frameworksGroup.children.append(frameworkFileRef)
        } else {
            // Create Frameworks group if it doesn't exist
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                let frameworksGroup = PBXGroup(sourceTree: .group, name: "Frameworks")
                xcodeproj.pbxproj.add(object: frameworksGroup)
                frameworksGroup.children.append(frameworkFileRef)
                mainGroup.children.append(frameworksGroup)
            }
        }

        // Create build file
        let buildFile = PBXBuildFile(file: frameworkFileRef)
        xcodeproj.pbxproj.add(object: buildFile)
        frameworksBuildPhase.files?.append(buildFile)

        // If embed is requested and it's a custom framework, add to embed frameworks phase
        if embed && !isSystemFramework {
            // Find or create embed frameworks build phase
            var embedPhase: PBXCopyFilesBuildPhase?
            for phase in target.buildPhases {
                if let copyPhase = phase as? PBXCopyFilesBuildPhase,
                    copyPhase.dstSubfolderSpec == .frameworks
                {
                    embedPhase = copyPhase
                    break
                }
            }

            if embedPhase == nil {
                embedPhase = PBXCopyFilesBuildPhase(
                    dstPath: "",
                    dstSubfolderSpec: .frameworks,
                    name: "Embed Frameworks"
                )
                xcodeproj.pbxproj.add(object: embedPhase!)
                target.buildPhases.append(embedPhase!)
            }

            // Create build file for embedding
            let embedBuildFile = PBXBuildFile(
                file: frameworkFileRef,
                settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]])
            xcodeproj.pbxproj.add(object: embedBuildFile)
            embedPhase?.files?.append(embedBuildFile)
        }

        // Save project
        try xcodeproj.write(path: Path(projectURL.path))

        return nil
    }
}
