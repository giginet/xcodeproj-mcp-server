import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct AddDependencyTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "add_dependency",
            description:
                "Add dependency between targets",
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
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                // Find the target
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
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
            case .xcproj(var file):
                guard let target = file.project.targets.first(where: { $0.name == targetName })
                else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }
                guard file.project.targets.contains(where: { $0.name == dependencyName }) else {
                    return CallTool.Result(
                        content: [
                            .text("Dependency target '\(dependencyName)' not found in project")
                        ]
                    )
                }

                let dependencyExists = target.commonProperties.dependencies.contains {
                    dependency in
                    if case .localTarget(let reference, _) = dependency {
                        return reference.targetName == dependencyName
                    }
                    return false
                }
                if dependencyExists {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' already depends on '\(dependencyName)'")
                        ]
                    )
                }

                // No container item proxy exists in xcproj: a dependency is
                // just a reference to the local target by name.
                XCProjSupport.modifyTarget(named: targetName, in: &file.project) { properties in
                    properties.dependencies.append(
                        .localTarget(
                            XCSchema.LocalTargetReference(targetName: dependencyName), []))
                }

                try file.save()
            }

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added dependency '\(dependencyName)' to target '\(targetName)'"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add dependency to Xcode project: \(error.localizedDescription)")
        }
    }
}
