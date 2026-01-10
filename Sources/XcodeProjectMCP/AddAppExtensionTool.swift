import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddAppExtensionTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_app_extension",
            description:
                "Add an App Extension target to the project and embed it in a host app. Supports Widget, Push Notification, Share, and other extension types.",
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
                        "description": .string("Name of the App Extension target to create"),
                    ]),
                    "extension_type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Type of extension (widget, notification_service, notification_content, share, today, action, file_provider, intents, intents_ui, custom)"
                        ),
                    ]),
                    "host_target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the host app target to embed the extension in"),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier for the extension (should be a child of the host app's bundle identifier)"
                        ),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Platform (iOS, macOS, tvOS, watchOS) - optional, defaults to iOS"),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string("Deployment target version (optional)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("extension_name"),
                    .string("extension_type"), .string("host_target_name"),
                    .string("bundle_identifier"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(extensionName) = arguments["extension_name"],
            case let .string(extensionTypeString) = arguments["extension_type"],
            case let .string(hostTargetName) = arguments["host_target_name"],
            case let .string(bundleIdentifier) = arguments["bundle_identifier"]
        else {
            throw MCPError.invalidParams(
                "project_path, extension_name, extension_type, host_target_name, and bundle_identifier are required"
            )
        }

        let platform: String
        if case let .string(plat) = arguments["platform"] {
            platform = plat
        } else {
            platform = "iOS"
        }

        let deploymentTarget: String?
        if case let .string(target) = arguments["deployment_target"] {
            deploymentTarget = target
        } else {
            deploymentTarget = nil
        }

        // Map extension type string to PBXProductType
        let (productType, _) = try mapExtensionType(extensionTypeString)

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Check if extension target already exists
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == extensionName }) {
                return CallTool.Result(
                    content: [
                        .text("Extension target '\(extensionName)' already exists in project")
                    ]
                )
            }

            // Find host app target
            guard
                let hostTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == hostTargetName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text("Host target '\(hostTargetName)' not found in project")
                    ]
                )
            }

            // Verify host target is an application
            guard hostTarget.productType == .application else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Host target '\(hostTargetName)' is not an application. App Extensions can only be embedded in applications."
                        )
                    ]
                )
            }

            // Create build configurations for extension target
            let extensionDebugConfig = XCBuildConfiguration(
                name: "Debug",
                buildSettings: [
                    "PRODUCT_NAME": .string(extensionName),
                    "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                    "INFOPLIST_FILE": .string("\(extensionName)/Info.plist"),
                    "SWIFT_VERSION": .string("5.0"),
                    "TARGETED_DEVICE_FAMILY": .string(platform == "iOS" ? "1,2" : "1"),
                    "CODE_SIGN_STYLE": .string("Automatic"),
                    "GENERATE_INFOPLIST_FILE": .string("YES"),
                    "CURRENT_PROJECT_VERSION": .string("1"),
                    "MARKETING_VERSION": .string("1.0"),
                    "SKIP_INSTALL": .string("YES"),
                    "DEBUG_INFORMATION_FORMAT": .string("dwarf"),
                ])

            let extensionReleaseConfig = XCBuildConfiguration(
                name: "Release",
                buildSettings: [
                    "PRODUCT_NAME": .string(extensionName),
                    "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                    "INFOPLIST_FILE": .string("\(extensionName)/Info.plist"),
                    "SWIFT_VERSION": .string("5.0"),
                    "TARGETED_DEVICE_FAMILY": .string(platform == "iOS" ? "1,2" : "1"),
                    "CODE_SIGN_STYLE": .string("Automatic"),
                    "GENERATE_INFOPLIST_FILE": .string("YES"),
                    "CURRENT_PROJECT_VERSION": .string("1"),
                    "MARKETING_VERSION": .string("1.0"),
                    "SKIP_INSTALL": .string("YES"),
                    "DEBUG_INFORMATION_FORMAT": .string("dwarf-with-dsym"),
                    "COPY_PHASE_STRIP": .string("NO"),
                ])

            // Add deployment target if specified
            if let deploymentTarget = deploymentTarget {
                let deploymentKey =
                    platform == "iOS"
                    ? "IPHONEOS_DEPLOYMENT_TARGET"
                    : platform == "macOS"
                        ? "MACOSX_DEPLOYMENT_TARGET"
                        : platform == "tvOS"
                            ? "TVOS_DEPLOYMENT_TARGET" : "WATCHOS_DEPLOYMENT_TARGET"
                extensionDebugConfig.buildSettings[deploymentKey] = .string(deploymentTarget)
                extensionReleaseConfig.buildSettings[deploymentKey] = .string(deploymentTarget)
            }

            xcodeproj.pbxproj.add(object: extensionDebugConfig)
            xcodeproj.pbxproj.add(object: extensionReleaseConfig)

            // Create extension configuration list
            let extensionConfigurationList = XCConfigurationList(
                buildConfigurations: [extensionDebugConfig, extensionReleaseConfig],
                defaultConfigurationName: "Release"
            )
            xcodeproj.pbxproj.add(object: extensionConfigurationList)

            // Create build phases
            let sourcesBuildPhase = PBXSourcesBuildPhase()
            xcodeproj.pbxproj.add(object: sourcesBuildPhase)

            let resourcesBuildPhase = PBXResourcesBuildPhase()
            xcodeproj.pbxproj.add(object: resourcesBuildPhase)

            let frameworksBuildPhase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: frameworksBuildPhase)

            // Create extension target
            let extensionTarget = PBXNativeTarget(
                name: extensionName,
                buildConfigurationList: extensionConfigurationList,
                buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
                productType: productType
            )
            extensionTarget.productName = extensionName
            xcodeproj.pbxproj.add(object: extensionTarget)

            // Create product reference for the extension
            let productReference = PBXFileReference(
                sourceTree: .buildProductsDir,
                explicitFileType: "wrapper.app-extension",
                path: "\(extensionName).appex",
                includeInIndex: false
            )
            xcodeproj.pbxproj.add(object: productReference)
            extensionTarget.product = productReference

            // Add product to Products group
            if let project = xcodeproj.pbxproj.rootObject,
                let productsGroup = project.productsGroup
            {
                productsGroup.children.append(productReference)
            }

            // Add extension target to project
            if let project = xcodeproj.pbxproj.rootObject {
                project.targets.append(extensionTarget)
            }

            // Create extension folder in main group
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                let extensionGroup = PBXGroup(sourceTree: .group, name: extensionName)
                xcodeproj.pbxproj.add(object: extensionGroup)
                mainGroup.children.append(extensionGroup)
            }

            // Create target dependency
            let containerProxy = PBXContainerItemProxy(
                containerPortal: .project(xcodeproj.pbxproj.rootObject!),
                proxyType: .nativeTarget,
                remoteInfo: extensionName
            )
            containerProxy.remoteGlobalID = .object(extensionTarget)
            xcodeproj.pbxproj.add(object: containerProxy)

            let targetDependency = PBXTargetDependency(
                name: extensionName,
                target: extensionTarget,
                targetProxy: containerProxy
            )
            xcodeproj.pbxproj.add(object: targetDependency)
            hostTarget.dependencies.append(targetDependency)

            // Create build file for embedding
            let buildFile = PBXBuildFile(
                file: productReference,
                settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]]
            )
            xcodeproj.pbxproj.add(object: buildFile)

            // Find or create "Embed App Extensions" copy files build phase
            var embedPhase = hostTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
                .first { $0.name == "Embed App Extensions" || $0.dstSubfolderSpec == .plugins }

            if embedPhase == nil {
                embedPhase = PBXCopyFilesBuildPhase(
                    dstPath: "",
                    dstSubfolderSpec: .plugins,
                    name: "Embed App Extensions"
                )
                xcodeproj.pbxproj.add(object: embedPhase!)
                hostTarget.buildPhases.append(embedPhase!)
            }

            embedPhase?.files?.append(buildFile)

            // Save project
            try xcodeproj.write(path: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully created App Extension '\(extensionName)' (\(extensionTypeString)) with bundle identifier '\(bundleIdentifier)' and embedded it in '\(hostTargetName)'"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to create App Extension in Xcode project: \(error.localizedDescription)")
        }
    }

    private func mapExtensionType(_ typeString: String) throws -> (
        PBXProductType, String
    ) {
        switch typeString.lowercased() {
        case "widget":
            return (.appExtension, "com.apple.widgetkit-extension")
        case "notification_service", "notificationservice":
            return (.appExtension, "com.apple.usernotifications.service")
        case "notification_content", "notificationcontent":
            return (.appExtension, "com.apple.usernotifications.content-extension")
        case "share":
            return (.appExtension, "com.apple.share-services")
        case "today":
            return (.appExtension, "com.apple.widget-extension")
        case "action":
            return (.appExtension, "com.apple.ui-services")
        case "file_provider", "fileprovider":
            return (.appExtension, "com.apple.fileprovider-nonui")
        case "intents":
            return (.intentsServiceExtension, "com.apple.intents-service")
        case "intents_ui", "intentsui":
            return (.appExtension, "com.apple.intents-ui-service")
        case "keyboard":
            return (.appExtension, "com.apple.keyboard-service")
        case "photo_editing", "photoediting":
            return (.appExtension, "com.apple.photo-editing")
        case "document_provider", "documentprovider":
            return (.appExtension, "com.apple.fileprovider-ui")
        case "custom":
            return (.appExtension, "")
        default:
            throw MCPError.invalidParams("Invalid extension type: \(typeString)")
        }
    }
}
