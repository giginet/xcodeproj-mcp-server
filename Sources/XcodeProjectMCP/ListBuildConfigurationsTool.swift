import Foundation
import MCP
import PathKit
import XcodeProj

public struct ListBuildConfigurationsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_build_configurations",
            description: "List all build configurations in an Xcode project",
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
            let projectURL = URL(fileURLWithPath: resolvedPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))
            let buildConfigurations = xcodeproj.pbxproj.buildConfigurations

            var configList: [String] = []
            for config in buildConfigurations {
                let configInfo = "- \(config.name)"
                configList.append(configInfo)
            }

            let result =
                configList.isEmpty
                ? "No build configurations found in the project."
                : configList.joined(separator: "\n")

            return CallTool.Result(
                content: [
                    .text("Build configurations in \(projectURL.lastPathComponent):\n\(result)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.descriptiveMessage)")
        }
    }
}
