import Foundation
import MCP
import PathKit
import XcodeProj

public struct ListFilesTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "list_files",
            description: "List all files in a specific target of an Xcode project",
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
                        "description": .string("Name of the target to list files for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        guard case let .string(targetName) = arguments["target_name"] else {
            throw MCPError.invalidParams("target_name is required")
        }

        do {
            let (loadedProject, _) = try projectLoader.load(projectPath: projectPath)

            var fileList: [String] = []
            switch loadedProject {
            case .pbxproj(let xcodeproj):
                // Find the target by name
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Get files from build phases
                for buildPhase in target.buildPhases {
                    if let sourcesBuildPhase = buildPhase as? PBXSourcesBuildPhase {
                        for file in sourcesBuildPhase.files ?? [] {
                            if let fileRef = file.file {
                                if let path = fileRef.path {
                                    fileList.append("- \(path)")
                                } else if let name = fileRef.name {
                                    fileList.append("- \(name)")
                                }
                            }
                        }
                    } else if let resourcesBuildPhase = buildPhase as? PBXResourcesBuildPhase {
                        for file in resourcesBuildPhase.files ?? [] {
                            if let fileRef = file.file {
                                if let path = fileRef.path {
                                    fileList.append("- \(path)")
                                } else if let name = fileRef.name {
                                    fileList.append("- \(name)")
                                }
                            }
                        }
                    } else if let frameworksBuildPhase = buildPhase as? PBXFrameworksBuildPhase {
                        for file in frameworksBuildPhase.files ?? [] {
                            if let fileRef = file.file {
                                if let path = fileRef.path {
                                    fileList.append("- \(path)")
                                } else if let name = fileRef.name {
                                    fileList.append("- \(name)")
                                }
                            }
                        }
                    }
                }
            case .xcproj(let file):
                guard let files = XCProjSupport.files(inTarget: targetName, of: file.project)
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }
                fileList = files.map { "- \($0)" }
            }

            let result =
                fileList.isEmpty
                ? "No files found in target '\(targetName)'." : fileList.joined(separator: "\n")

            return CallTool.Result(
                content: [
                    .text("Files in target '\(targetName)':\n\(result)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)")
        }
    }
}
