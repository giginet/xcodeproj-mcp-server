import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_file",
            description: "Add a file to an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the file to add (absolute, or relative to the base directory the server was started with -- not to the directory containing the .xcodeproj)"
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the group to add the file to (optional, defaults to main group)"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to add the file to (optional)"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("file_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(filePath) = arguments["file_path"]
        else {
            throw MCPError.invalidParams("project_path and file_path are required")
        }

        let groupName: String?
        if case let .string(group) = arguments["group_name"] {
            groupName = group
        } else {
            groupName = nil
        }

        let targetName: String?
        if case let .string(target) = arguments["target_name"] {
            targetName = target
        } else {
            targetName = nil
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            // Resolve and validate the file path
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the group to add the file to
            let targetGroup: PBXGroup
            if let groupName = groupName {
                // Find group by name, path, or hierarchical path (e.g. "Parent/Child")
                do {
                    targetGroup = try GroupFinder.findGroup(
                        named: groupName, in: xcodeproj.pbxproj)
                } catch {
                    throw MCPError.invalidParams("Group '\(groupName)' not found in project")
                }
            } else {
                // Use main group
                guard let project = try xcodeproj.pbxproj.rootProject(),
                    let mainGroup = project.mainGroup
                else {
                    throw MCPError.internalError("Main group not found in project")
                }
                targetGroup = mainGroup
            }

            // Create file reference
            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
            // A PBXFileReference with sourceTree .group resolves its `path` relative to
            // its parent group's own resolved directory, which chains up to the
            // directory containing the .xcodeproj -- not the MCP server's sandbox
            // basePath. Those two directories only coincide when the .xcodeproj sits
            // directly at basePath; for a nested project (e.g. <repo>/apps/ios/Foo.xcodeproj
            // with basePath == <repo>) resolving relative to basePath produces a path
            // that gets the project's own subdirectory prefix applied twice at build time.
            let projectDirPath = Path(projectURL.deletingLastPathComponent().path)
            let targetGroupPath = try? targetGroup.fullPath(sourceRoot: projectDirPath)
            let relativePath =
                PathUtility.relativePath(
                    from: (targetGroupPath ?? projectDirPath).string, to: resolvedFilePath)
                ?? resolvedFilePath
            let fileReference = PBXFileReference(
                sourceTree: .group,
                name: fileName,
                path: relativePath
            )
            xcodeproj.pbxproj.add(object: fileReference)

            // Add file to group
            targetGroup.children.append(fileReference)
            fileReference.parent = targetGroup

            // Add file to target if specified
            if let targetName = targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Create build file
                let buildFile = PBXBuildFile(file: fileReference)
                xcodeproj.pbxproj.add(object: buildFile)

                // Add to appropriate build phase based on file extension
                let fileExtension = URL(fileURLWithPath: resolvedFilePath).pathExtension
                    .lowercased()

                if ["swift", "m", "mm", "c", "cpp", "cc", "cxx"].contains(fileExtension) {
                    // Source file - add to compile sources
                    if let sourcesBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXSourcesBuildPhase
                    }) as? PBXSourcesBuildPhase {
                        sourcesBuildPhase.files?.append(buildFile)
                    } else {
                        // Create sources build phase if it doesn't exist
                        let sourcesBuildPhase = PBXSourcesBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: sourcesBuildPhase)
                        target.buildPhases.append(sourcesBuildPhase)
                    }
                } else if ["h", "hpp", "hxx"].contains(fileExtension) {
                    // Header file - add to headers build phase
                    if let headersBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXHeadersBuildPhase
                    }) as? PBXHeadersBuildPhase {
                        headersBuildPhase.files?.append(buildFile)
                    } else {
                        // Create headers build phase if it doesn't exist
                        let headersBuildPhase = PBXHeadersBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: headersBuildPhase)
                        target.buildPhases.append(headersBuildPhase)
                    }
                } else {
                    // Resource file - add to copy bundle resources
                    if let resourcesBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXResourcesBuildPhase
                    }) as? PBXResourcesBuildPhase {
                        resourcesBuildPhase.files?.append(buildFile)
                    } else {
                        // Create resources build phase if it doesn't exist
                        let resourcesBuildPhase = PBXResourcesBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: resourcesBuildPhase)
                        target.buildPhases.append(resourcesBuildPhase)
                    }
                }
            }

            // Write project
            try xcodeproj.write(path: Path(projectURL.path))

            let targetInfo = targetName != nil ? " to target '\(targetName!)'" : ""
            let groupInfo = groupName != nil ? " in group '\(groupName!)'" : ""

            // Referencing a file that is not on disk yet is legitimate, so this is not an
            // error. It is worth reporting though: the most common cause is a file_path
            // resolved against the wrong directory, which otherwise silently produces a
            // reference that Xcode shows as missing.
            var message = "Successfully added file '\(fileName)'\(targetInfo)\(groupInfo)"
            if !FileManager.default.fileExists(atPath: resolvedFilePath) {
                message += """


                    Warning: no file exists at '\(resolvedFilePath)'. The reference was added \
                    anyway. Note that a relative file_path resolves against the base directory \
                    the server was started with, not the directory containing the .xcodeproj.
                    """
            }

            return CallTool.Result(
                content: [
                    .text(message)
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add file to Xcode project: \(error.localizedDescription)")
        }
    }
}
