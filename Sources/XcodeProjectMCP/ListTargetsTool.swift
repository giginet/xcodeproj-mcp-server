import Foundation
import MCP
import PathKit
import XcodeProj

public struct ListTargetsTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "list_targets",
            description: "List all targets in an Xcode project",
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
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            var targetList: [String] = []
            switch loadedProject {
            case .pbxproj(let xcodeproj):
                for target in xcodeproj.pbxproj.nativeTargets {
                    targetList.append(
                        "- \(target.name) (\(target.productType?.rawValue ?? "unknown"))")
                }
            case .xcproj(let file):
                for summary in XCProjSupport.targetSummaries(of: file.project) {
                    targetList.append("- \(summary.name) (\(summary.productType))")
                }
            }

            let result =
                targetList.isEmpty
                ? "No targets found in the project." : targetList.joined(separator: "\n")

            return CallTool.Result(
                content: [
                    .text("Targets in \(projectURL.lastPathComponent):\n\(result)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.descriptiveMessage)")
        }
    }
}
