import Foundation
import MCP
import PathKit
import XcodeProj

public struct CreateXcodeprojTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "create_xcodeproj",
            description: "Create a new Xcode project file (.xcodeproj)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the Xcode project"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory path where the project will be created (relative to current directory)"
                        ),
                    ]),
                    "organization_name": .object([
                        "type": .string("string"),
                        "description": .string("Organization name for the project"),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Bundle identifier prefix"),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "enum": .array([.string("pbxproj"), .string("xcproj")]),
                        "description": .string(
                            "Project file format: 'pbxproj' (default, legacy format readable by all Xcode versions) or 'xcproj' (JSON format, requires Xcode 27.2+)"
                        ),
                    ]),
                ]),
                "required": .array([.string("project_name"), .string("path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectName) = arguments["project_name"],
            case let .string(pathString) = arguments["path"]
        else {
            throw MCPError.invalidParams("project_name and path are required")
        }

        let organizationName: String
        if case let .string(org) = arguments["organization_name"] {
            organizationName = org
        } else {
            organizationName = ""
        }

        let bundleIdentifier: String
        if case let .string(bundle) = arguments["bundle_identifier"] {
            bundleIdentifier = bundle
        } else {
            bundleIdentifier = "com.example"
        }

        let format: ProjectFormat
        if case let .string(formatString) = arguments["format"] {
            guard let parsedFormat = ProjectFormat(rawValue: formatString) else {
                throw MCPError.invalidParams(
                    "format must be one of: "
                        + ProjectFormat.allCases.map(\.rawValue).joined(separator: ", "))
            }
            format = parsedFormat
        } else {
            format = .pbxproj
        }

        do {
            // Resolve and validate the path
            let resolvedPath = try pathUtility.resolvePath(from: pathString)
            let projectPath = Path(resolvedPath) + "\(projectName).xcodeproj"

            if format == .xcproj {
                let project = try XCProjSupport.makeNewProject(
                    name: projectName,
                    organizationName: organizationName,
                    bundleIdentifier: bundleIdentifier
                )
                let bundleURL = URL(fileURLWithPath: projectPath.string)
                try FileManager.default.createDirectory(
                    at: bundleURL, withIntermediateDirectories: true)
                try XCProjFile(project: project, bundleURL: bundleURL).save()

                return CallTool.Result(
                    content: [
                        .text("Successfully created Xcode project at: \(projectPath.string)")
                    ]
                )
            }

            // Create the .pbxproj file using XcodeProj
            let pbxproj = PBXProj()

            // Create project groups
            let mainGroup = PBXGroup(sourceTree: .group)
            pbxproj.add(object: mainGroup)
            let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
            pbxproj.add(object: productsGroup)

            // Create project build configurations
            let debugConfig = XCBuildConfiguration(
                name: "Debug",
                buildSettings: [
                    "ORGANIZATION_NAME": .string(organizationName)
                ])
            let releaseConfig = XCBuildConfiguration(
                name: "Release",
                buildSettings: [
                    "ORGANIZATION_NAME": .string(organizationName)
                ])
            pbxproj.add(object: debugConfig)
            pbxproj.add(object: releaseConfig)

            // Create project configuration list
            let configurationList = XCConfigurationList(
                buildConfigurations: [debugConfig, releaseConfig],
                defaultConfigurationName: "Release"
            )
            pbxproj.add(object: configurationList)

            // Create target build configurations with bundle identifier
            let targetDebugConfig = XCBuildConfiguration(
                name: "Debug",
                buildSettings: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string("\(bundleIdentifier).\(projectName)"),
                    "PRODUCT_NAME": .string("$(TARGET_NAME)"),
                    "SWIFT_VERSION": .string("5.0"),
                ])
            let targetReleaseConfig = XCBuildConfiguration(
                name: "Release",
                buildSettings: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string("\(bundleIdentifier).\(projectName)"),
                    "PRODUCT_NAME": .string("$(TARGET_NAME)"),
                    "SWIFT_VERSION": .string("5.0"),
                ])
            pbxproj.add(object: targetDebugConfig)
            pbxproj.add(object: targetReleaseConfig)

            // Create target configuration list
            let targetConfigurationList = XCConfigurationList(
                buildConfigurations: [targetDebugConfig, targetReleaseConfig],
                defaultConfigurationName: "Release"
            )
            pbxproj.add(object: targetConfigurationList)

            // Create product reference for the app target
            let productReference = PBXFileReference(
                sourceTree: .buildProductsDir,
                name: "\(projectName).app",
                explicitFileType: "wrapper.application"
            )
            pbxproj.add(object: productReference)
            productsGroup.children.append(productReference)

            // Create build phases
            let sourcesBuildPhase = PBXSourcesBuildPhase(files: [])
            pbxproj.add(object: sourcesBuildPhase)

            let frameworksBuildPhase = PBXFrameworksBuildPhase(files: [])
            pbxproj.add(object: frameworksBuildPhase)

            let resourcesBuildPhase = PBXResourcesBuildPhase(files: [])
            pbxproj.add(object: resourcesBuildPhase)

            // Create app target with bundle identifier
            let appTarget = PBXNativeTarget(
                name: projectName,
                buildConfigurationList: targetConfigurationList,
                buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
                productName: projectName,
                productType: .application
            )
            appTarget.product = productReference
            pbxproj.add(object: appTarget)

            // Create project
            let project = PBXProject(
                name: projectName,
                buildConfigurationList: configurationList,
                compatibilityVersion: "Xcode 14.0",
                preferredProjectObjectVersion: 56,
                minimizedProjectReferenceProxies: 0,
                mainGroup: mainGroup,
                developmentRegion: "en",
                knownRegions: ["en", "Base"],
                productsGroup: productsGroup,
                targets: [appTarget]
            )
            pbxproj.add(object: project)
            pbxproj.rootObject = project

            // Create workspace
            let workspaceData = XCWorkspaceData(children: [])
            let workspace = XCWorkspace(data: workspaceData)

            // Create xcodeproj
            let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)

            // Write project
            try xcodeproj.write(path: projectPath)

            return CallTool.Result(
                content: [
                    .text("Successfully created Xcode project at: \(projectPath.string)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to create Xcode project: \(error.descriptiveMessage)")
        }
    }
}
