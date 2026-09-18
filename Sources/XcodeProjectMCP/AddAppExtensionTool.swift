import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public enum ExtensionType: String, CaseIterable, Sendable {
    case widget
    case notificationService = "notification_service"
    case notificationContent = "notification_content"
    case share
    case today
    case action
    case fileProvider = "file_provider"
    case intents
    case intentsUI = "intents_ui"
    case keyboard
    case photoEditing = "photo_editing"
    case documentProvider = "document_provider"
    case custom

    public init?(from string: String) {
        let lowercased = string.lowercased()
        if let type = ExtensionType(rawValue: lowercased) {
            self = type
        } else {
            // Handle alternative naming conventions
            switch lowercased {
            case "notificationservice":
                self = .notificationService
            case "notificationcontent":
                self = .notificationContent
            case "fileprovider":
                self = .fileProvider
            case "intentsui":
                self = .intentsUI
            case "photoediting":
                self = .photoEditing
            case "documentprovider":
                self = .documentProvider
            default:
                return nil
            }
        }
    }

    public var productType: PBXProductType {
        switch self {
        case .intents:
            return .intentsServiceExtension
        default:
            return .appExtension
        }
    }

    public var extensionPointIdentifier: String {
        switch self {
        case .widget:
            return "com.apple.widgetkit-extension"
        case .notificationService:
            return "com.apple.usernotifications.service"
        case .notificationContent:
            return "com.apple.usernotifications.content-extension"
        case .share:
            return "com.apple.share-services"
        case .today:
            return "com.apple.widget-extension"
        case .action:
            return "com.apple.ui-services"
        case .fileProvider:
            return "com.apple.fileprovider-nonui"
        case .intents:
            return "com.apple.intents-service"
        case .intentsUI:
            return "com.apple.intents-ui-service"
        case .keyboard:
            return "com.apple.keyboard-service"
        case .photoEditing:
            return "com.apple.photo-editing"
        case .documentProvider:
            return "com.apple.fileprovider-ui"
        case .custom:
            return ""
        }
    }
}

public struct AddAppExtensionTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
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

        // Map extension type string to ExtensionType enum
        guard let extensionType = ExtensionType(from: extensionTypeString) else {
            throw MCPError.invalidParams("Invalid extension type: \(extensionTypeString)")
        }
        let productType = extensionType.productType

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                return try addToPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL,
                    extensionName: extensionName, extensionTypeString: extensionTypeString,
                    hostTargetName: hostTargetName, bundleIdentifier: bundleIdentifier,
                    platform: platform, deploymentTarget: deploymentTarget,
                    productType: productType)
            case .xcproj(var file):
                if file.project.targets.contains(where: { $0.name == extensionName }) {
                    return CallTool.Result(
                        content: [
                            .text("Extension target '\(extensionName)' already exists in project")
                        ]
                    )
                }
                guard
                    let hostTarget = file.project.targets.first(where: {
                        $0.name == hostTargetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text("Host target '\(hostTargetName)' not found in project")
                        ]
                    )
                }
                guard
                    hostTarget.commonProperties.productTypeID?.rawValue
                        == "com.apple.product-type.application"
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Host target '\(hostTargetName)' is not an application. App Extensions can only be embedded in applications."
                            )
                        ]
                    )
                }

                // Flat build settings (Debug/Release only diverge in debug-info
                // format, which cannot be expressed inline in xcproj)
                var buildSettings: [String: XCSchema.BuildSetting] = [
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
                ]
                if let deploymentTarget = deploymentTarget {
                    let deploymentKey =
                        switch platform {
                        case "iOS": "IPHONEOS_DEPLOYMENT_TARGET"
                        case "macOS": "MACOSX_DEPLOYMENT_TARGET"
                        case "tvOS": "TVOS_DEPLOYMENT_TARGET"
                        case "watchOS": "WATCHOS_DEPLOYMENT_TARGET"
                        default: throw MCPError.invalidParams("Unknown platform: \(platform)")
                        }
                    buildSettings[deploymentKey] = .string(deploymentTarget)
                }

                let productFileName = "\(extensionName).appex"
                let extensionTarget = XCSchema.Target.native(
                    XCSchema.CommonTargetProperties(
                        name: extensionName,
                        objectID: XCProjSupport.makeObjectID(),
                        configurationListDebugID: nil,
                        dependencies: [],
                        buildPhases: [
                            .sources(
                                XCSchema.BuildPhaseProperties(
                                    objectID: XCProjSupport.makeObjectID(), name: nil)),
                            .frameworks(
                                XCSchema.BuildPhaseProperties(
                                    objectID: XCProjSupport.makeObjectID(), name: nil)),
                            .resources(
                                XCSchema.BuildPhaseProperties(
                                    objectID: XCProjSupport.makeObjectID(), name: nil)),
                        ],
                        buildRules: [],
                        specializedConfigurations: [],
                        buildSettings: buildSettings,
                        product: .namePath(
                            XCSchema.NamePath(components: [
                                .child("Products"), .child(productFileName),
                            ])),
                        productTypeID: XCSchema.ProductTypeID(rawValue: productType.rawValue),
                        testHostTarget: nil,
                        legacyProvisioningStyle: nil,
                        legacyTeamID: nil,
                        lastSwiftUpdateCheck: nil,
                        lastSwiftMigration: nil,
                        packageProductTargetMembers: []
                    )
                )
                file.project.targets.append(extensionTarget)

                // The host app embeds the extension via an "Embed App
                // Extensions" copy phase; the membership entry lives on the
                // extension's product file reference.
                let embedPhaseName = "Embed App Extensions"
                XCProjSupport.modifyTarget(named: hostTargetName, in: &file.project) {
                    properties in
                    properties.dependencies.append(
                        .localTarget(
                            XCSchema.LocalTargetReference(targetName: extensionName), []))
                    let hasEmbedPhase = properties.buildPhases.contains { phase in
                        if case .copy(let copyProperties) = phase {
                            return copyProperties.bundleBasePath == .plugInsDir
                                || copyProperties.baseProperties.name == embedPhaseName
                        }
                        return false
                    }
                    if !hasEmbedPhase {
                        properties.buildPhases.append(
                            .copy(
                                XCSchema.CopyFilesBuildPhaseProperties(
                                    objectID: XCProjSupport.makeObjectID(),
                                    name: embedPhaseName,
                                    bundleBasePath: .plugInsDir,
                                    relativePath: "",
                                    scope: .always)))
                    }
                }

                var embedAttributes = XCProjSupport.emptyBuildFileAttributes()
                embedAttributes.headerPreservation = .removeOnCopy
                let productReference = XCSchema.FileReference(
                    objectID: nil,
                    path: try XCSchema.FilePath(base: .buildProducts, path: productFileName),
                    explicitFileType: XCSchema.FileTypeID(rawValue: "wrapper.app-extension"),
                    expectedSignature: nil,
                    textEncoding: nil,
                    lineEnding: nil,
                    includeInIndex: false,
                    buildFiles: [
                        XCProjSupport.makeBuildFile(
                            targetName: hostTargetName, kind: .copy, phaseName: embedPhaseName,
                            properties: XCSchema.BuildFileProperties(
                                platformFilters: [],
                                additionalBuildFlags: nil,
                                assetTags: [],
                                attributes: embedAttributes))
                    ]
                )

                // Add the product to a "Products" group, creating it when missing
                var productsGroupIndexPath = XCProjTreeEditor.findGroup(
                    named: "Products", in: file.project.topLevelReferences)
                if productsGroupIndexPath == nil {
                    file.project.topLevelReferences.append(
                        .group(
                            XCSchema.Group(
                                objectID: nil, name: "Products", path: "",
                                includeInIndex: nil, children: [])))
                    productsGroupIndexPath = [file.project.topLevelReferences.count - 1]
                }
                XCProjTreeEditor.append(
                    .fileReference(productReference), toGroupAt: productsGroupIndexPath,
                    in: &file.project.topLevelReferences)

                // Create extension folder at the top level
                file.project.topLevelReferences.append(
                    .group(
                        XCSchema.Group(
                            objectID: nil, name: extensionName, path: "", includeInIndex: nil,
                            children: [])))

                try file.save()

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully created App Extension '\(extensionName)' (\(extensionTypeString)) with bundle identifier '\(bundleIdentifier)' and embedded it in '\(hostTargetName)'"
                        )
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to create App Extension in Xcode project: \(error.localizedDescription)")
        }
    }

    private func addToPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, extensionName: String, extensionTypeString: String,
        hostTargetName: String, bundleIdentifier: String, platform: String,
        deploymentTarget: String?, productType: PBXProductType
    ) throws -> CallTool.Result {
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
                switch platform {
                case "iOS": "IPHONEOS_DEPLOYMENT_TARGET"
                case "macOS": "MACOSX_DEPLOYMENT_TARGET"
                case "tvOS": "TVOS_DEPLOYMENT_TARGET"
                case "watchOS": "WATCHOS_DEPLOYMENT_TARGET"
                default: throw MCPError.invalidParams("Unknown platform: \(platform)")
                }
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
    }
}
