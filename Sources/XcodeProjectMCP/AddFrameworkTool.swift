import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddFrameworkTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_framework",
            description: "Add framework dependencies",
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
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

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

            // Determine if this is a system framework or custom framework
            let isSystemFramework =
                !frameworkName.contains("/") && !frameworkName.hasSuffix(".framework")
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
                "Failed to add framework to Xcode project: \(error.descriptiveMessage)")
        }
    }
}
