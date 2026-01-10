import Foundation
import MCP
import PathKit
import XcodeProj

public struct RemoveAppExtensionTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_app_extension",
            description:
                "Remove an App Extension target from the project and its embedding from the host app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "extension_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the App Extension target to remove"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("extension_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(extensionName) = arguments["extension_name"]
        else {
            throw MCPError.invalidParams("project_path and extension_name are required")
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the extension target to remove
            guard
                let extensionTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == extensionName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text("Extension target '\(extensionName)' not found in project")
                    ]
                )
            }

            // Verify it's an app extension
            let extensionProductTypes: [PBXProductType] = [
                .appExtension,
                .extensionKitExtension,
                .watchExtension,
                .watch2Extension,
                .tvExtension,
                .messagesExtension,
                .stickerPack,
                .intentsServiceExtension,
            ]

            guard extensionProductTypes.contains(extensionTarget.productType ?? .none) else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Target '\(extensionName)' is not an App Extension. Use remove_target for other target types."
                        )
                    ]
                )
            }

            let productReference = extensionTarget.product

            // Remove extension from "Embed App Extensions" build phase in all targets
            for target in xcodeproj.pbxproj.nativeTargets {
                // Remove target dependency
                target.dependencies.removeAll { dependency in
                    dependency.target == extensionTarget
                }

                // Remove from embed phases
                for buildPhase in target.buildPhases {
                    if let copyPhase = buildPhase as? PBXCopyFilesBuildPhase {
                        // Remove build files referencing the extension product
                        copyPhase.files?.removeAll { buildFile in
                            if buildFile.file == productReference {
                                xcodeproj.pbxproj.delete(object: buildFile)
                                return true
                            }
                            return false
                        }

                        // Remove empty embed phases if desired (optional cleanup)
                        if copyPhase.files?.isEmpty == true
                            && copyPhase.name == "Embed App Extensions"
                        {
                            target.buildPhases.removeAll { $0 == copyPhase }
                            xcodeproj.pbxproj.delete(object: copyPhase)
                        }
                    }
                }
            }

            // Remove build phases from extension target
            for buildPhase in extensionTarget.buildPhases {
                xcodeproj.pbxproj.delete(object: buildPhase)
            }

            // Remove build configuration list
            if let configList = extensionTarget.buildConfigurationList {
                for config in configList.buildConfigurations {
                    xcodeproj.pbxproj.delete(object: config)
                }
                xcodeproj.pbxproj.delete(object: configList)
            }

            // Remove product reference if exists
            if let productRef = productReference {
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
                project.targets.removeAll { $0 == extensionTarget }
            }

            // Remove extension group if exists
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                removeExtensionGroup(
                    from: mainGroup, extensionName: extensionName, xcodeproj: xcodeproj)
            }

            // Remove the target itself
            xcodeproj.pbxproj.delete(object: extensionTarget)

            // Save project
            try xcodeproj.write(path: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully removed App Extension '\(extensionName)' from project and all host app embeddings"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove App Extension from Xcode project: \(error.localizedDescription)")
        }
    }

    private func removeExtensionGroup(
        from group: PBXGroup, extensionName: String, xcodeproj: XcodeProj
    ) {
        group.children.removeAll { element in
            if let groupElement = element as? PBXGroup,
                groupElement.name == extensionName
            {
                xcodeproj.pbxproj.delete(object: groupElement)
                return true
            }
            return false
        }

        // Recursively check child groups
        for child in group.children {
            if let childGroup = child as? PBXGroup {
                removeExtensionGroup(
                    from: childGroup, extensionName: extensionName, xcodeproj: xcodeproj)
            }
        }
    }
}
