import Foundation
import MCP
import PathKit
import XcodeProj

public struct DuplicateTargetTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "duplicate_target",
            description:
                "Duplicate an existing target (pbxproj format only; xcproj-format projects from Xcode 27.2 are not supported yet)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "source_target": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to duplicate"),
                    ]),
                    "new_target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name for the new target"),
                    ]),
                    "new_bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Bundle identifier for the new target (optional)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("source_target"), .string("new_target_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(sourceTargetName) = arguments["source_target"],
            case let .string(newTargetName) = arguments["new_target_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, source_target, and new_target_name are required")
        }

        let newBundleIdentifier: String?
        if case let .string(bundleId) = arguments["new_bundle_identifier"] {
            newBundleIdentifier = bundleId
        } else {
            newBundleIdentifier = nil
        }

        try projectLoader.requirePBXProj(projectPath: projectPath, toolName: "duplicate_target")

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the source target
            guard
                let sourceTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == sourceTargetName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text("Source target '\(sourceTargetName)' not found in project")
                    ]
                )
            }

            // Check if target with new name already exists
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == newTargetName }) {
                return CallTool.Result(
                    content: [
                        .text("Target '\(newTargetName)' already exists in project")
                    ]
                )
            }

            // Duplicate build configuration list
            let newBuildConfigurations: [XCBuildConfiguration] =
                sourceTarget.buildConfigurationList?.buildConfigurations.map { sourceConfig in
                    var newBuildSettings = sourceConfig.buildSettings

                    // Update product name and bundle identifier
                    newBuildSettings["PRODUCT_NAME"] = .string(newTargetName)
                    if let newBundleIdentifier = newBundleIdentifier {
                        newBuildSettings["BUNDLE_IDENTIFIER"] = .string(newBundleIdentifier)
                    }

                    // Update info plist if it references the target name
                    if let infoPlist = newBuildSettings["INFOPLIST_FILE"]?.stringValue,
                        infoPlist.contains(sourceTargetName)
                    {
                        let newInfoPlist = infoPlist.replacingOccurrences(
                            of: sourceTargetName, with: newTargetName)
                        newBuildSettings["INFOPLIST_FILE"] = .string(newInfoPlist)
                    }

                    let newConfig = XCBuildConfiguration(
                        name: sourceConfig.name, buildSettings: newBuildSettings)
                    xcodeproj.pbxproj.add(object: newConfig)
                    return newConfig
                } ?? []

            let newConfigList = XCConfigurationList(
                buildConfigurations: newBuildConfigurations,
                defaultConfigurationName: sourceTarget.buildConfigurationList?
                    .defaultConfigurationName ?? "Release"
            )
            xcodeproj.pbxproj.add(object: newConfigList)

            // Duplicate build phases
            let newBuildPhases: [PBXBuildPhase] = sourceTarget.buildPhases.compactMap {
                sourcePhase in
                if let sourcesPhase = sourcePhase as? PBXSourcesBuildPhase {
                    let newPhase = PBXSourcesBuildPhase(files: sourcesPhase.files ?? [])
                    xcodeproj.pbxproj.add(object: newPhase)
                    return newPhase
                } else if let resourcesPhase = sourcePhase as? PBXResourcesBuildPhase {
                    let newPhase = PBXResourcesBuildPhase(files: resourcesPhase.files ?? [])
                    xcodeproj.pbxproj.add(object: newPhase)
                    return newPhase
                } else if let frameworksPhase = sourcePhase as? PBXFrameworksBuildPhase {
                    let newPhase = PBXFrameworksBuildPhase(files: frameworksPhase.files ?? [])
                    xcodeproj.pbxproj.add(object: newPhase)
                    return newPhase
                } else if let shellScriptPhase = sourcePhase as? PBXShellScriptBuildPhase {
                    let newPhase = PBXShellScriptBuildPhase(
                        name: shellScriptPhase.name,
                        inputPaths: shellScriptPhase.inputPaths,
                        outputPaths: shellScriptPhase.outputPaths,
                        shellPath: shellScriptPhase.shellPath ?? "/bin/sh",
                        shellScript: shellScriptPhase.shellScript
                    )
                    xcodeproj.pbxproj.add(object: newPhase)
                    return newPhase
                } else if let copyFilesPhase = sourcePhase as? PBXCopyFilesBuildPhase {
                    let newPhase = PBXCopyFilesBuildPhase(
                        dstPath: copyFilesPhase.dstPath,
                        dstSubfolderSpec: copyFilesPhase.dstSubfolderSpec,
                        name: copyFilesPhase.name,
                        files: copyFilesPhase.files ?? []
                    )
                    xcodeproj.pbxproj.add(object: newPhase)
                    return newPhase
                }
                return nil
            }

            // Create new target
            let newTarget = PBXNativeTarget(
                name: newTargetName,
                buildConfigurationList: newConfigList,
                buildPhases: newBuildPhases,
                productType: sourceTarget.productType
            )
            newTarget.productName = newTargetName

            // Copy dependencies
            for sourceDependency in sourceTarget.dependencies {
                if let dependencyTarget = sourceDependency.target {
                    // Create new proxy
                    let newProxy = PBXContainerItemProxy(
                        containerPortal: .project(xcodeproj.pbxproj.rootObject!),
                        remoteGlobalID: .object(dependencyTarget),
                        proxyType: .nativeTarget,
                        remoteInfo: dependencyTarget.name
                    )
                    xcodeproj.pbxproj.add(object: newProxy)

                    // Create new dependency
                    let newDependency = PBXTargetDependency(
                        name: sourceDependency.name,
                        target: dependencyTarget,
                        targetProxy: newProxy
                    )
                    xcodeproj.pbxproj.add(object: newDependency)
                    newTarget.dependencies.append(newDependency)
                }
            }

            xcodeproj.pbxproj.add(object: newTarget)

            // Add target to project
            if let project = xcodeproj.pbxproj.rootObject {
                project.targets.append(newTarget)
            }

            // Create target folder in main group
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                let targetGroup = PBXGroup(sourceTree: .group, name: newTargetName)
                xcodeproj.pbxproj.add(object: targetGroup)
                mainGroup.children.append(targetGroup)
            }

            // Save project
            try xcodeproj.write(path: Path(projectURL.path))

            let bundleIdText =
                newBundleIdentifier != nil
                ? " with bundle identifier '\(newBundleIdentifier!)'" : ""
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully duplicated target '\(sourceTargetName)' as '\(newTargetName)'\(bundleIdText)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to duplicate target in Xcode project: \(error.localizedDescription)")
        }
    }
}
