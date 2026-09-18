import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct RemoveTargetTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_target",
            description:
                "Remove an existing target",
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
                        "description": .string("Name of the target to remove"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                return try removeFromPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL, targetName: targetName)
            case .xcproj(var file):
                guard
                    let targetIndex = file.project.targets.firstIndex(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }
                let target = file.project.targets[targetIndex]
                let removedPhaseIDs = XCProjSupport.phaseObjectIDs(of: target)

                // Remove the target itself
                file.project.targets.remove(at: targetIndex)

                // Remove dependencies on the removed target from other targets
                for index in file.project.targets.indices {
                    file.project.targets[index] = XCProjSupport.modifying(
                        file.project.targets[index]
                    ) { properties in
                        properties.dependencies.removeAll { dependency in
                            if case .localTarget(let reference, _) = dependency {
                                return reference.targetName == targetName
                            }
                            return false
                        }
                    }
                }

                // Sweep the whole tree, dropping membership entries that point
                // at the removed target (by name or by its phase object IDs)
                XCProjTreeEditor.mutateFileReferences(in: &file.project.topLevelReferences) {
                    fileReference in
                    fileReference.buildFiles.removeAll { buildFile in
                        XCProjSupport.buildFile(
                            buildFile, belongsTo: targetName, phaseIDs: removedPhaseIDs)
                    }
                }

                // Remove the product reference from the tree, if any
                if case .namePath(let namePath) = target.commonProperties.product,
                    let productName = namePath.components.last?.childName
                {
                    _ = XCProjTreeEditor.removeFirstFileReference(
                        in: &file.project.topLevelReferences
                    ) { fileReference in
                        let storedPath = fileReference.path.stringRepresentation
                        let storedName =
                            storedPath.split(separator: "/").last.map(String.init) ?? storedPath
                        return storedName == productName
                    }
                }

                // Remove the target's group, mirroring the pbxproj arm
                if let groupIndexPath = XCProjTreeEditor.findGroup(
                    named: targetName, in: file.project.topLevelReferences)
                {
                    if groupIndexPath.count == 1 {
                        file.project.topLevelReferences.remove(at: groupIndexPath[0])
                    } else {
                        XCProjTreeEditor.modifyGroup(
                            at: Array(groupIndexPath.dropLast()),
                            in: &file.project.topLevelReferences
                        ) { group in
                            group.children.remove(at: groupIndexPath[groupIndexPath.count - 1])
                        }
                    }
                }

                try file.save()

                return CallTool.Result(
                    content: [
                        .text("Successfully removed target '\(targetName)' from project")
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to remove target from Xcode project: \(error.localizedDescription)")
        }
    }

    private func removeFromPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, targetName: String
    ) throws -> CallTool.Result {
        // Find the target to remove
        guard
            let targetIndex = xcodeproj.pbxproj.nativeTargets.firstIndex(where: {
                $0.name == targetName
            })
        else {
            return CallTool.Result(
                content: [
                    .text("Target '\(targetName)' not found in project")
                ]
            )
        }

        let target = xcodeproj.pbxproj.nativeTargets[targetIndex]

        // Remove target dependencies from other targets
        for otherTarget in xcodeproj.pbxproj.nativeTargets {
            otherTarget.dependencies.removeAll { dependency in
                dependency.target == target
            }
        }

        // Remove build phases
        for buildPhase in target.buildPhases {
            xcodeproj.pbxproj.delete(object: buildPhase)
        }

        // Remove build configuration list
        if let configList = target.buildConfigurationList {
            for config in configList.buildConfigurations {
                xcodeproj.pbxproj.delete(object: config)
            }
            xcodeproj.pbxproj.delete(object: configList)
        }

        // Remove product reference if exists
        if let productRef = target.product {
            // Remove from products group
            if let project = xcodeproj.pbxproj.rootObject,
                let productsGroup = project.productsGroup
            {
                productsGroup.children.removeAll { $0 == productRef }
            }
            xcodeproj.pbxproj.delete(object: productRef)
        }

        // Remove target from project
        if let project = xcodeproj.pbxproj.rootObject {
            project.targets.removeAll { $0 == target }
        }

        // Remove target group if exists
        if let project = try xcodeproj.pbxproj.rootProject(),
            let mainGroup = project.mainGroup
        {
            // Find and remove target folder
            func removeTargetGroup(from group: PBXGroup) {
                group.children.removeAll { element in
                    if let groupElement = element as? PBXGroup,
                        groupElement.name == targetName
                    {
                        xcodeproj.pbxproj.delete(object: groupElement)
                        return true
                    }
                    return false
                }

                // Recursively check child groups
                for child in group.children {
                    if let childGroup = child as? PBXGroup {
                        removeTargetGroup(from: childGroup)
                    }
                }
            }
            removeTargetGroup(from: mainGroup)
        }

        // Remove the target itself
        xcodeproj.pbxproj.delete(object: target)

        // Save project
        try xcodeproj.write(path: Path(projectURL.path))

        return CallTool.Result(
            content: [
                .text("Successfully removed target '\(targetName)' from project")
            ]
        )
    }
}
