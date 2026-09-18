import Foundation
import MCP
import PathKit
import XcodeProj
import XcodeProjectFormat

public struct AddTargetTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "add_target",
            description:
                "Create a new target",
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
                        "description": .string("Name of the target to create"),
                    ]),
                    "product_type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Product type (application, framework, staticFramework, xcFramework, dynamicLibrary, staticLibrary, bundle, unitTestBundle, uiTestBundle, appExtension, extensionKitExtension, commandLineTool, watchApp, watch2App, watch2AppContainer, watchExtension, watch2Extension, tvExtension, messagesApplication, messagesExtension, stickerPack, xpcService, ocUnitTestBundle, xcodeExtension, instrumentsPackage, intentsServiceExtension, onDemandInstallCapableApplication, metalLibrary, driverExtension, systemExtension)"
                        ),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Bundle identifier for the target"),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Platform (iOS, macOS, tvOS, watchOS) - optional, defaults to iOS)"),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string("Deployment target version (optional)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_type"),
                    .string("bundle_identifier"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(productTypeString) = arguments["product_type"],
            case let .string(bundleIdentifier) = arguments["bundle_identifier"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, product_type, and bundle_identifier are required")
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

        // Map product type string to PBXProductType
        let productType: PBXProductType
        switch productTypeString.lowercased() {
        case "application", "app":
            productType = .application
        case "framework":
            productType = .framework
        case "staticframework", "static_framework":
            productType = .staticFramework
        case "xcframework", "xc_framework":
            productType = .xcFramework
        case "dynamiclibrary", "dynamic_library":
            productType = .dynamicLibrary
        case "staticlibrary", "static_library":
            productType = .staticLibrary
        case "bundle":
            productType = .bundle
        case "unittestbundle", "unit_test_bundle":
            productType = .unitTestBundle
        case "uitestbundle", "ui_test_bundle":
            productType = .uiTestBundle
        case "appextension", "app_extension":
            productType = .appExtension
        case "extensionkitextension", "extensionkit_extension":
            productType = .extensionKitExtension
        case "commandlinetool", "command_line_tool":
            productType = .commandLineTool
        case "watchapp", "watch_app":
            productType = .watchApp
        case "watch2app", "watch2_app", "watch_2_app":
            productType = .watch2App
        case "watch2appcontainer", "watch2_app_container", "watch_2_app_container":
            productType = .watch2AppContainer
        case "watchextension", "watch_extension":
            productType = .watchExtension
        case "watch2extension", "watch2_extension", "watch_2_extension":
            productType = .watch2Extension
        case "tvextension", "tv_extension":
            productType = .tvExtension
        case "messagesapplication", "messages_application":
            productType = .messagesApplication
        case "messagesextension", "messages_extension":
            productType = .messagesExtension
        case "stickerpack", "sticker_pack":
            productType = .stickerPack
        case "xpcservice", "xpc_service":
            productType = .xpcService
        case "ocunittestbundle", "oc_unit_test_bundle":
            productType = .ocUnitTestBundle
        case "xcodeextension", "xcode_extension":
            productType = .xcodeExtension
        case "instrumentspackage", "instruments_package":
            productType = .instrumentsPackage
        case "intentsserviceextension", "intents_service_extension":
            productType = .intentsServiceExtension
        case "ondemandinstallcapableapplication", "on_demand_install_capable_application":
            productType = .onDemandInstallCapableApplication
        case "metallibrary", "metal_library":
            productType = .metalLibrary
        case "driverextension", "driver_extension":
            productType = .driverExtension
        case "systemextension", "system_extension":
            productType = .systemExtension
        default:
            throw MCPError.invalidParams("Invalid product type: \(productTypeString)")
        }

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            let targetExists: Bool
            switch loadedProject {
            case .pbxproj(let xcodeproj):
                targetExists = xcodeproj.pbxproj.nativeTargets.contains { $0.name == targetName }
            case .xcproj(let file):
                targetExists = file.project.targets.contains { $0.name == targetName }
            }
            if targetExists {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' already exists in project")
                    ]
                )
            }

            switch loadedProject {
            case .pbxproj(let xcodeproj):
                try addToPBXProj(
                    xcodeproj: xcodeproj, projectURL: projectURL, targetName: targetName,
                    productType: productType, bundleIdentifier: bundleIdentifier,
                    platform: platform, deploymentTarget: deploymentTarget)
            case .xcproj(var file):
                // xcproj stores one flat build settings dictionary per target;
                // the pbxproj arm writes the same values into Debug and Release.
                var buildSettings: [String: XCSchema.BuildSetting] = [
                    "PRODUCT_NAME": .string(targetName),
                    "BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                    "INFOPLIST_FILE": .string("\(targetName)/Info.plist"),
                    "SWIFT_VERSION": .string("5.0"),
                    "TARGETED_DEVICE_FAMILY": .string(platform == "iOS" ? "1,2" : "1"),
                ]
                if let deploymentTarget = deploymentTarget {
                    let deploymentKey =
                        platform == "iOS"
                        ? "IPHONEOS_DEPLOYMENT_TARGET"
                        : platform == "macOS"
                            ? "MACOSX_DEPLOYMENT_TARGET"
                            : platform == "tvOS"
                                ? "TVOS_DEPLOYMENT_TARGET" : "WATCHOS_DEPLOYMENT_TARGET"
                    buildSettings[deploymentKey] = .string(deploymentTarget)
                }

                let target = XCSchema.Target.native(
                    XCSchema.CommonTargetProperties(
                        name: targetName,
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
                        product: nil,
                        productTypeID: XCSchema.ProductTypeID(rawValue: productType.rawValue),
                        testHostTarget: nil,
                        legacyProvisioningStyle: nil,
                        legacyTeamID: nil,
                        lastSwiftUpdateCheck: nil,
                        lastSwiftMigration: nil,
                        packageProductTargetMembers: []
                    )
                )
                file.project.targets.append(target)

                // Create target folder at the top level (mirrors the pbxproj
                // arm's group in the main group)
                let targetGroup = XCSchema.Group(
                    objectID: nil, name: targetName, path: "", includeInIndex: nil, children: [])
                file.project.topLevelReferences.append(.group(targetGroup))

                try file.save()
            }

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully created target '\(targetName)' with product type '\(productTypeString)' and bundle identifier '\(bundleIdentifier)'"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to create target in Xcode project: \(error.descriptiveMessage)")
        }
    }

    private func addToPBXProj(
        xcodeproj: XcodeProj, projectURL: URL, targetName: String, productType: PBXProductType,
        bundleIdentifier: String, platform: String, deploymentTarget: String?
    ) throws {
        // Create build configurations for target
        let targetDebugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: [
                "PRODUCT_NAME": .string(targetName),
                "BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                "INFOPLIST_FILE": .string("\(targetName)/Info.plist"),
                "SWIFT_VERSION": .string("5.0"),
                "TARGETED_DEVICE_FAMILY": .string(platform == "iOS" ? "1,2" : "1"),
            ])

        let targetReleaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: [
                "PRODUCT_NAME": .string(targetName),
                "BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                "INFOPLIST_FILE": .string("\(targetName)/Info.plist"),
                "SWIFT_VERSION": .string("5.0"),
                "TARGETED_DEVICE_FAMILY": .string(platform == "iOS" ? "1,2" : "1"),
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
            targetDebugConfig.buildSettings[deploymentKey] = .string(deploymentTarget)
            targetReleaseConfig.buildSettings[deploymentKey] = .string(deploymentTarget)
        }

        xcodeproj.pbxproj.add(object: targetDebugConfig)
        xcodeproj.pbxproj.add(object: targetReleaseConfig)

        // Create target configuration list
        let targetConfigurationList = XCConfigurationList(
            buildConfigurations: [targetDebugConfig, targetReleaseConfig],
            defaultConfigurationName: "Release"
        )
        xcodeproj.pbxproj.add(object: targetConfigurationList)

        // Create build phases
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        xcodeproj.pbxproj.add(object: sourcesBuildPhase)

        let resourcesBuildPhase = PBXResourcesBuildPhase()
        xcodeproj.pbxproj.add(object: resourcesBuildPhase)

        let frameworksBuildPhase = PBXFrameworksBuildPhase()
        xcodeproj.pbxproj.add(object: frameworksBuildPhase)

        // Create target
        let target = PBXNativeTarget(
            name: targetName,
            buildConfigurationList: targetConfigurationList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productType: productType
        )
        target.productName = targetName
        xcodeproj.pbxproj.add(object: target)

        // Add target to project
        if let project = xcodeproj.pbxproj.rootObject {
            project.targets.append(target)
        }

        // Create target folder in main group
        if let project = try xcodeproj.pbxproj.rootProject(),
            let mainGroup = project.mainGroup
        {
            let targetGroup = PBXGroup(sourceTree: .group, name: targetName)
            xcodeproj.pbxproj.add(object: targetGroup)
            mainGroup.children.append(targetGroup)
        }

        // Save project
        try xcodeproj.write(path: Path(projectURL.path))
    }
}

extension PBXProductType {
    var fileExtension: String? {
        switch self {
        case .application, .watchApp, .watch2App, .watch2AppContainer, .messagesApplication,
            .onDemandInstallCapableApplication:
            return "app"
        case .framework, .staticFramework:
            return "framework"
        case .xcFramework:
            return "xcframework"
        case .staticLibrary:
            return "a"
        case .dynamicLibrary:
            return "dylib"
        case .bundle:
            return "bundle"
        case .unitTestBundle, .uiTestBundle, .ocUnitTestBundle:
            return "xctest"
        case .appExtension, .extensionKitExtension, .watchExtension, .watch2Extension, .tvExtension,
            .messagesExtension, .stickerPack, .xcodeExtension, .intentsServiceExtension,
            .driverExtension, .systemExtension:
            return "appex"
        case .commandLineTool:
            return nil
        case .xpcService:
            return "xpc"
        case .instrumentsPackage:
            return "instrdst"
        case .metalLibrary:
            return "metallib"
        case .none:
            return nil
        }
    }
}
