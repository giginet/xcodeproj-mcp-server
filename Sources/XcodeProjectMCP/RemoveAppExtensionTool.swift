import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct RemoveAppExtensionTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
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
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                return try removeFromPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL, extensionName: extensionName)
            case .xcproj(var file):
                guard
                    let extensionTarget = file.project.targets.first(where: {
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
                let extensionProductTypeIDs: Set<String> = [
                    "com.apple.product-type.app-extension",
                    "com.apple.product-type.extensionkit-extension",
                    "com.apple.product-type.watchkit-extension",
                    "com.apple.product-type.watchkit2-extension",
                    "com.apple.product-type.tv-app-extension",
                    "com.apple.product-type.app-extension.messages",
                    "com.apple.product-type.app-extension.messages-sticker-pack",
                    "com.apple.product-type.app-extension.intents-service",
                ]
                guard
                    let productTypeID = extensionTarget.commonProperties.productTypeID?.rawValue,
                    extensionProductTypeIDs.contains(productTypeID)
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Target '\(extensionName)' is not an App Extension. Use remove_target for other target types."
                            )
                        ]
                    )
                }

                let removedPhaseIDs = XCProjSupport.phaseObjectIDs(of: extensionTarget)

                // Remove the target and dependencies on it from all other targets
                file.project.targets.removeAll { $0.name == extensionName }
                for index in file.project.targets.indices {
                    file.project.targets[index] = XCProjSupport.modifying(
                        file.project.targets[index]
                    ) { properties in
                        properties.dependencies.removeAll { dependency in
                            if case .localTarget(let reference, _) = dependency {
                                return reference.targetName == extensionName
                            }
                            return false
                        }
                    }
                }

                // Remove the product reference; its embed membership entry
                // (the host's copy-phase build file) is removed with it
                _ = XCProjTreeEditor.removeFirstFileReference(
                    in: &file.project.topLevelReferences
                ) { fileReference in
                    let storedPath = fileReference.path.stringRepresentation
                    let storedName =
                        storedPath.split(separator: "/").last.map(String.init) ?? storedPath
                    return storedName == "\(extensionName).appex"
                }

                // Sweep remaining memberships pointing at the removed target
                XCProjTreeEditor.mutateFileReferences(in: &file.project.topLevelReferences) {
                    fileReference in
                    fileReference.buildFiles.removeAll { buildFile in
                        XCProjSupport.buildFile(
                            buildFile, belongsTo: extensionName, phaseIDs: removedPhaseIDs)
                    }
                }

                // Drop now-empty "Embed App Extensions" phases, mirroring the
                // pbxproj arm's cleanup: a copy phase is empty when no file
                // reference in the tree maps into it any more.
                var referencedPhases:
                    [(target: String, kind: XCSchema.BuildPhase.Kind, name: String?)] = []
                var referencedPhaseIDs = Set<XCSchema.ObjectID>()
                XCProjTreeEditor.forEachFileReference(in: file.project.topLevelReferences) {
                    fileReference in
                    for buildFile in fileReference.buildFiles {
                        switch buildFile.buildPhase {
                        case .named(let target, let kind, let name):
                            referencedPhases.append((target.targetName, kind, name))
                        case .objectID(let id):
                            referencedPhaseIDs.insert(id)
                        }
                    }
                }
                for index in file.project.targets.indices {
                    let hostName = file.project.targets[index].name
                    file.project.targets[index] = XCProjSupport.modifying(
                        file.project.targets[index]
                    ) { properties in
                        properties.buildPhases.removeAll { phase in
                            guard case .copy(let copyProperties) = phase,
                                copyProperties.baseProperties.name == "Embed App Extensions"
                            else { return false }
                            if let id = copyProperties.baseProperties.objectID,
                                referencedPhaseIDs.contains(id)
                            {
                                return false
                            }
                            let stillReferenced = referencedPhases.contains { reference in
                                reference.target == hostName && reference.kind == .copy
                                    && (reference.name == copyProperties.baseProperties.name
                                        || reference.name == nil)
                            }
                            return !stillReferenced
                        }
                    }
                }

                // Remove the extension's group, if any
                if let groupIndexPath = XCProjTreeEditor.findGroup(
                    named: extensionName, in: file.project.topLevelReferences)
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
                        .text(
                            "Successfully removed App Extension '\(extensionName)' from project and all host app embeddings"
                        )
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to remove App Extension from Xcode project: \(error.localizedDescription)")
        }
    }

    private func removeFromPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, extensionName: String
    ) throws -> CallTool.Result {
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
