import Foundation
import MCP
import PathKit
import XcodeProj

public struct RemoveFileTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }
    public func tool() -> Tool {
        Tool(
            name: "remove_file",
            description:
                "Remove a file from the Xcode project",
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
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            // Resolve and validate the file path
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)

            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
            // Use relative path from project for comparison
            let relativePath =
                pathUtility.makeRelativePath(from: resolvedFilePath) ?? resolvedFilePath
            var removedFromTargets: [String] = []
            var fileRemoved = false

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                try removeFromPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL,
                    filePath: filePath, relativePath: relativePath, fileName: fileName,
                    removedFromTargets: &removedFromTargets, fileRemoved: &fileRemoved)
            case .xcproj(var file):
                // Membership entries live on the file reference, so they are
                // removed together with it; recover the target names first for
                // the result message.
                let removed = XCProjTreeEditor.removeFirstFileReference(
                    in: &file.project.topLevelReferences
                ) { fileReference in
                    let storedPath = fileReference.path.stringRepresentation
                    let storedName =
                        storedPath.split(separator: "/").last.map(String.init) ?? storedPath
                    return storedPath == relativePath || storedPath == filePath
                        || storedName == fileName
                }
                if let removed {
                    removedFromTargets = XCProjSupport.targetNames(
                        referencedBy: removed, in: file.project)
                    fileRemoved = true
                    try file.save()
                }
            }

            if fileRemoved {
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
                "Failed to remove file from Xcode project: \(error.descriptiveMessage)")
        }
    }

    private func removeFromPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, filePath: String, relativePath: String,
        fileName: String, removedFromTargets: inout [String], fileRemoved: inout Bool
    ) throws {
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
        }
    }
}
