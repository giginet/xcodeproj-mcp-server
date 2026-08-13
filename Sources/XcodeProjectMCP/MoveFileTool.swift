import Foundation
import MCP
import PathKit
import XcodeProj

public struct MoveFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "move_file",
            description: "Move or rename a file within the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "old_path": .object([
                        "type": .string("string"),
                        "description": .string("Current path of the file to move"),
                    ]),
                    "new_path": .object([
                        "type": .string("string"),
                        "description": .string("New path for the file"),
                    ]),
                    "move_on_disk": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to also move the file on disk (optional, defaults to false)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("old_path"), .string("new_path"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(oldPath) = arguments["old_path"],
            case let .string(newPath) = arguments["new_path"]
        else {
            throw MCPError.invalidParams("project_path, old_path, and new_path are required")
        }

        let moveOnDisk: Bool
        if case let .bool(move) = arguments["move_on_disk"] {
            moveOnDisk = move
        } else {
            moveOnDisk = false
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            // Resolve and validate the old and new file paths
            let resolvedOldPath = try pathUtility.resolvePath(from: oldPath)
            let resolvedNewPath = try pathUtility.resolvePath(from: newPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let oldFileName = URL(fileURLWithPath: resolvedOldPath).lastPathComponent
            let newFileName = URL(fileURLWithPath: resolvedNewPath).lastPathComponent

            // Use relative paths from project for comparison and updates
            let oldRelativePath =
                pathUtility.makeRelativePath(from: resolvedOldPath) ?? resolvedOldPath
            let newRelativePath =
                pathUtility.makeRelativePath(from: resolvedNewPath) ?? resolvedNewPath

            let projectDirPath = Path(projectURL.deletingLastPathComponent().path)

            var fileMoved = false

            // Find and update file references
            for fileRef in xcodeproj.pbxproj.fileReferences {
                if fileRef.path == oldRelativePath || fileRef.path == oldPath
                    || fileRef.name == oldFileName || fileRef.path == oldFileName
                {
                    // Update the file reference
                    fileRef.path = referencePath(
                        for: fileRef,
                        movedTo: resolvedNewPath,
                        in: xcodeproj.pbxproj,
                        projectDirectory: projectDirPath
                    )
                    fileRef.name = newFileName
                    fileMoved = true
                }
            }

            if fileMoved {
                try xcodeproj.write(path: Path(projectURL.path))

                // Optionally move on disk
                if moveOnDisk {
                    let oldURL = URL(fileURLWithPath: resolvedOldPath)
                    let newURL = URL(fileURLWithPath: resolvedNewPath)

                    // Create parent directory if needed
                    let newParentDir = newURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: newParentDir.path) {
                        try FileManager.default.createDirectory(
                            at: newParentDir, withIntermediateDirectories: true)
                    }

                    // Move the file
                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                    }
                }

                return CallTool.Result(
                    content: [
                        .text("Successfully moved \(oldFileName) to \(newRelativePath)")
                    ]
                )
            } else {
                return CallTool.Result(
                    content: [
                        .text("File not found in project: \(oldFileName)")
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to move file in Xcode project: \(error.localizedDescription)")
        }
    }

    /// Computes the `path` to store on a moved file reference.
    ///
    /// A `PBXFileReference` with `sourceTree: .group` resolves its `path` relative to
    /// the directory of the group that owns it, which chains up to the directory
    /// containing the .xcodeproj -- not the MCP server's sandbox basePath. Storing a
    /// basePath-relative path breaks the reference whenever the owning group carries a
    /// `path` of its own, because the group's directory then gets applied on top of it.
    /// This mirrors how `AddFileTool` computes the path when it first adds the file.
    private func referencePath(
        for fileRef: PBXFileReference,
        movedTo resolvedNewPath: String,
        in pbxproj: PBXProj,
        projectDirectory: Path
    ) -> String {
        let fallback =
            pathUtility.makeRelativePath(from: resolvedNewPath) ?? resolvedNewPath

        switch fileRef.sourceTree {
        case .group:
            // `parent` is not guaranteed to be populated for references decoded from
            // disk, so locate the owning group by looking for it among the children.
            let owningGroup =
                (fileRef.parent as? PBXGroup)
                ?? pbxproj.groups.first { group in
                    group.children.contains { $0 === fileRef }
                }
            let groupDirectory =
                owningGroup.flatMap { try? $0.fullPath(sourceRoot: projectDirectory) }
                ?? projectDirectory
            return PathUtility.relativePath(from: groupDirectory.string, to: resolvedNewPath)
                ?? fallback
        case .sourceRoot:
            // Resolved relative to the directory containing the .xcodeproj.
            return PathUtility.relativePath(
                from: projectDirectory.string, to: resolvedNewPath) ?? fallback
        default:
            // Absolute or build-setting-relative trees carry their own semantics; leave
            // the existing behaviour untouched.
            return fallback
        }
    }
}
