import Foundation
import MCP
import XcodeProj
import PathKit

public struct ListTargetsTool: Sendable {
    public func tool() -> Tool {
        Tool(
            name: "list_targets",
            description: "List all targets in an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file")
                    ])
                ]),
                "required": .array([.string("project_path")])
            ])
        )
    }
    
    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }
        
        let projectURL = URL(fileURLWithPath: projectPath)
        
        do {
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))
            let targets = xcodeproj.pbxproj.nativeTargets
            
            var targetList: [String] = []
            for target in targets {
                let targetInfo = "- \(target.name) (\(target.productType?.rawValue ?? "unknown"))"
                targetList.append(targetInfo)
            }
            
            let result = targetList.isEmpty ? "No targets found in the project." : targetList.joined(separator: "\n")
            
            return CallTool.Result(
                content: [
                    .text("Targets in \(projectURL.lastPathComponent):\n\(result)")
                ]
            )
        } catch {
            throw MCPError.internalError("Failed to read Xcode project: \(error.localizedDescription)")
        }
    }
}