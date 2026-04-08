import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_synchronized_folder",
            description: "Add a synchronized folder reference to an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the folder to add (relative to project root or absolute)"),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the group to add the folder to (optional, defaults to main group)"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to add the folder to (optional)"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("folder_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(folderPath) = arguments["folder_path"]
        else {
            throw MCPError.invalidParams("project_path and folder_path are required")
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
            let projectURL = URL(filePath: resolvedProjectPath)

            // Resolve and validate the folder path
            let resolvedFolderPath = try pathUtility.resolvePath(from: folderPath)

            // Verify that the path is actually a directory
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(
                atPath: resolvedFolderPath, isDirectory: &isDirectory)
            {
                throw MCPError.invalidParams("Folder does not exist at path: \(folderPath)")
            }
            if !isDirectory.boolValue {
                throw MCPError.invalidParams("Path is not a directory: \(folderPath)")
            }

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Create file system synchronized root group
            let folderName = URL(filePath: resolvedFolderPath).lastPathComponent
            // Use relative path from project for folder reference
            let relativePath =
                pathUtility.makeRelativePath(from: resolvedFolderPath) ?? resolvedFolderPath

            let folderReference = PBXFileSystemSynchronizedRootGroup(
                sourceTree: .group,
                path: relativePath,
                name: folderName
            )
            xcodeproj.pbxproj.add(object: folderReference)

            // Find the group to add the folder to
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

            // Add folder to group
            targetGroup.children.append(folderReference)

            // Add folder to target if specified
            if let targetName = targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Create build file for the folder
                let buildFile = PBXBuildFile(file: folderReference)
                xcodeproj.pbxproj.add(object: buildFile)

                // Add to resources build phase
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

            // Write project
            try xcodeproj.write(path: Path(projectURL.path))

            let targetInfo = targetName != nil ? " to target '\(targetName!)'" : ""
            let groupInfo = groupName != nil ? " in group '\(groupName!)'" : ""

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added folder reference '\(folderName)'\(targetInfo)\(groupInfo)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add folder to Xcode project: \(error.localizedDescription)")
        }
    }
}
