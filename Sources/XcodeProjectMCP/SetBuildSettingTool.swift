import Foundation
import MCP
import PathKit
import XcodeProj

public struct SetBuildSettingTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "set_build_setting",
            description:
                "Modify build settings for a target",
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
                        "description": .string("Name of the target to modify"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration name (Debug, Release, or All)"),
                    ]),
                    "setting_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the build setting to modify"),
                    ]),
                    "setting_value": .object([
                        "type": .string("string"),
                        "description": .string("New value for the build setting"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("configuration"),
                    .string("setting_name"), .string("setting_value"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(configuration) = arguments["configuration"],
            case let .string(settingName) = arguments["setting_name"],
            case let .string(settingValue) = arguments["setting_value"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, configuration, setting_name, and setting_value are required"
            )
        }

        do {
            let (loadedProject, projectURL) = try projectLoader.load(projectPath: projectPath)

            var modifiedConfigurations: [String] = []

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

                // Get the build configuration list for the target
                guard let configList = target.buildConfigurationList else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' has no build configuration list")
                        ]
                    )
                }

                // Handle "All" configuration
                if configuration.lowercased() == "all" {
                    for config in configList.buildConfigurations {
                        config.buildSettings[settingName] = .string(settingValue)
                        modifiedConfigurations.append(config.name)
                    }
                } else {
                    // Find specific configuration
                    guard
                        let config = configList.buildConfigurations.first(where: {
                            $0.name == configuration
                        })
                    else {
                        return CallTool.Result(
                            content: [
                                .text(
                                    "Configuration '\(configuration)' not found for target '\(targetName)'"
                                )
                            ]
                        )
                    }

                    config.buildSettings[settingName] = .string(settingValue)
                    modifiedConfigurations.append(config.name)
                }

                // Save project
                try xcodeproj.write(path: Path(projectURL.path))
            case .xcproj(var file):
                guard file.project.targets.contains(where: { $0.name == targetName }) else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' not found in project")
                        ]
                    )
                }

                // xcproj stores one flat build settings dictionary per target;
                // per-configuration overrides only exist through xcconfig files,
                // so a configuration-scoped write is not representable inline.
                guard configuration.lowercased() == "all" else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Configuration-specific build settings are not supported for xcproj projects: xcproj stores one flat build settings dictionary per target. Use configuration 'all' to set '\(settingName)' for all configurations. The project file was not modified."
                            )
                        ]
                    )
                }

                XCProjSupport.modifyTarget(named: targetName, in: &file.project) { properties in
                    properties.buildSettings[settingName] = .string(settingValue)
                }
                modifiedConfigurations = XCProjSupport.configurationNames(of: file.project)
                try file.save()
            }

            let configurationsText = modifiedConfigurations.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully set '\(settingName)' to '\(settingValue)' for target '\(targetName)' in configuration(s): \(configurationsText)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to set build setting in Xcode project: \(error.localizedDescription)")
        }
    }
}
