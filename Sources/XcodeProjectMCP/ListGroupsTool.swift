import Foundation
import MCP
import PathKit
import XcodeProj

public struct ListGroupsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_groups",
            description:
                "List all groups, folder references, and file system synchronized groups in an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ])
                ]),
                "required": .array([.string("project_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        do {
            // Resolve and validate the path
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Get the root project and main group
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            var groupList: [String] = []

            // Recursively traverse groups starting from main group
            traverseGroup(mainGroup, path: "", groupList: &groupList)

            // Also include the products group if it exists and is not already included
            if let productsGroup = project.productsGroup,
                !groupList.contains(where: { $0.contains("Products") })
            {
                traverseGroup(productsGroup, path: "", groupList: &groupList)
            }

            let result =
                groupList.isEmpty
                ? "No groups, folder references, or synchronized groups found in project."
                : groupList.joined(separator: "\n")

            let titleMessage =
                "Groups, folder references, and synchronized groups in project:\n\(result)"

            return CallTool.Result(
                content: [
                    .text(titleMessage)
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.descriptiveMessage)")
        }
    }

    private func traverseGroup(_ group: PBXGroup, path: String, groupList: inout [String]) {
        // Get the group name - use name if available, otherwise use path
        let groupName = group.name ?? group.path ?? "Unnamed Group"

        // Build the full path for this group
        let currentPath = path.isEmpty ? groupName : "\(path)/\(groupName)"

        // Add this group to the list if it has a meaningful name
        // Skip only if it's the root group with no name or path
        let shouldInclude = group.name != nil || group.path != nil
        if shouldInclude {
            groupList.append("- \(currentPath)")
        }

        // Process all children (groups, folder references, and synchronized groups)
        for child in group.children {
            if let childGroup = child as? PBXGroup {
                // For child groups, use current path if this group should be included, otherwise use the parent path
                let childPath = shouldInclude ? currentPath : path
                traverseGroup(childGroup, path: childPath, groupList: &groupList)
            } else if let syncGroup = child as? PBXFileSystemSynchronizedRootGroup {
                // Handle PBXFileSystemSynchronizedRootGroup (Xcode 15+ feature)
                let syncGroupName = syncGroup.path ?? "Unnamed Sync Group"
                let syncGroupPath =
                    shouldInclude
                    ? "\(currentPath)/\(syncGroupName)"
                    : path.isEmpty ? syncGroupName : "\(path)/\(syncGroupName)"
                groupList.append("- \(syncGroupPath) (file system synchronized)")
            } else if let folderRef = child as? PBXFileReference,
                folderRef.lastKnownFileType == "folder"
            {
                // Handle folder references
                let folderName = folderRef.name ?? folderRef.path ?? "Unnamed Folder"
                let folderPath =
                    shouldInclude
                    ? "\(currentPath)/\(folderName)"
                    : path.isEmpty ? folderName : "\(path)/\(folderName)"
                groupList.append("- \(folderPath) (folder reference)")
            }
        }
    }

}
