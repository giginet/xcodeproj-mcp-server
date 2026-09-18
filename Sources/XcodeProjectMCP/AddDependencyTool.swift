import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddDependencyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_dependency",
            description: "Add dependency between targets",
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
                        "description": .string(
                            "Name of the target that will depend on another target"),
                    ]),
                    "dependency_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to depend on"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("dependency_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(dependencyName) = arguments["dependency_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and dependency_name are required")
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' not found in project")
                    ]
                )
            }

            // Find the dependency target
            guard
                let dependencyTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == dependencyName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text("Dependency target '\(dependencyName)' not found in project")
                    ]
                )
            }

            // Check if dependency already exists
            let dependencyExists = target.dependencies.contains { dependency in
                dependency.target == dependencyTarget
            }

            if dependencyExists {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' already depends on '\(dependencyName)'")
                    ]
                )
            }

            // Create container item proxy
            let containerItemProxy = PBXContainerItemProxy(
                containerPortal: .project(xcodeproj.pbxproj.rootObject!),
                remoteGlobalID: .object(dependencyTarget),
                proxyType: .nativeTarget,
                remoteInfo: dependencyName
            )
            xcodeproj.pbxproj.add(object: containerItemProxy)

            // Create target dependency
            let targetDependency = PBXTargetDependency(
                name: dependencyName,
                target: dependencyTarget,
                targetProxy: containerItemProxy
            )
            xcodeproj.pbxproj.add(object: targetDependency)

            // Add dependency to target
            target.dependencies.append(targetDependency)

            // Save project
            try xcodeproj.write(path: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added dependency '\(dependencyName)' to target '\(targetName)'"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add dependency to Xcode project: \(error.descriptiveMessage)")
        }
    }
}
