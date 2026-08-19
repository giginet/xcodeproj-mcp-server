import Foundation
import MCP
import PathKit
import XcodeProj

public struct RemoveFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }
    public func tool() -> Tool {
        Tool(
            name: "remove_file",
            description: "Remove a file from the Xcode project",
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
                            "Path to the file to remove (absolute, or relative to the base directory the server was started with)"
                        ),
                    ]),
                    "remove_from_disk": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to also delete the file from disk (optional, defaults to false)"
                        ),
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

        let removeFromDisk: Bool
        if case let .bool(remove) = arguments["remove_from_disk"] {
            removeFromDisk = remove
        } else {
            removeFromDisk = false
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            // Resolve and validate the file path
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
            // Use relative path from project for comparison
            let relativePath =
                pathUtility.makeRelativePath(from: resolvedFilePath) ?? resolvedFilePath
            var removedFromTargets: [String] = []
            var fileRemoved = false

            // Find and remove file references from build phases
            for target in xcodeproj.pbxproj.nativeTargets {
                // Check sources build phase
                if let sourcesBuildPhase = target.buildPhases.first(where: {
                    $0 is PBXSourcesBuildPhase
                }) as? PBXSourcesBuildPhase {
                    if let fileIndex = sourcesBuildPhase.files?.firstIndex(where: { buildFile in
                        if let fileRef = buildFile.file as? PBXFileReference {
                            return fileRef.path == relativePath || fileRef.path == filePath
                                || fileRef.name == fileName || fileRef.path == fileName
                        }
                        return false
                    }) {
                        sourcesBuildPhase.files?.remove(at: fileIndex)
                        removedFromTargets.append(target.name)
                        fileRemoved = true
                    }
                }

                // Check resources build phase
                if let resourcesBuildPhase = target.buildPhases.first(where: {
                    $0 is PBXResourcesBuildPhase
                }) as? PBXResourcesBuildPhase {
                    if let fileIndex = resourcesBuildPhase.files?.firstIndex(where: { buildFile in
                        if let fileRef = buildFile.file as? PBXFileReference {
                            return fileRef.path == relativePath || fileRef.path == filePath
                                || fileRef.name == fileName || fileRef.path == fileName
                        }
                        return false
                    }) {
                        resourcesBuildPhase.files?.remove(at: fileIndex)
                        if !removedFromTargets.contains(target.name) {
                            removedFromTargets.append(target.name)
                        }
                        fileRemoved = true
                    }
                }
            }

            // Remove from project groups
            func removeFromGroup(_ group: PBXGroup) -> Bool {
                let children = group.children
                if let index = children.firstIndex(where: { element in
                    if let fileRef = element as? PBXFileReference {
                        return fileRef.path == relativePath || fileRef.path == filePath
                            || fileRef.name == fileName || fileRef.path == fileName
                    }
                    return false
                }) {
                    group.children.remove(at: index)
                    return true
                }

                // Recursively check child groups
                for child in children {
                    if let childGroup = child as? PBXGroup {
                        if removeFromGroup(childGroup) {
                            return true
                        }
                    }
                }
                return false
            }

            if let project = xcodeproj.pbxproj.rootObject,
                let mainGroup = project.mainGroup
            {
                if removeFromGroup(mainGroup) {
                    fileRemoved = true
                }
            }

            if fileRemoved {
                try xcodeproj.write(path: Path(projectURL.path))

                // Optionally remove from disk
                if removeFromDisk {
                    let fileURL = URL(fileURLWithPath: resolvedFilePath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully removed \(fileName) from project. Removed from targets: \(removedFromTargets.joined(separator: ", "))"
                        )
                    ]
                )
            } else {
                return CallTool.Result(
                    content: [
                        .text("File not found in project: \(fileName)")
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to remove file from Xcode project: \(error.localizedDescription)")
        }
    }
}
