import Foundation
import MCP
import PathKit
import XcodeProj

public struct GetBuildSettingsTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "get_build_settings",
            description: "Get build settings for a specific target in an Xcode project",
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
                        "description": .string("Name of the target to get build settings for"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration name (optional, defaults to Debug)"),
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

        let configurationName: String
        if case let .string(config) = arguments["configuration"] {
            configurationName = config
        } else {
            configurationName = "Debug"
        }

        do {
            let (loadedProject, _) = try projectLoader.load(projectPath: projectPath)

            var settingsList: [String] = []
            var note: String?
            switch loadedProject {
            case .pbxproj(let xcodeproj):
                // Find the target
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Get the build configuration for the target
                guard let configList = target.buildConfigurationList else {
                    throw MCPError.invalidParams(
                        "Target '\(targetName)' has no build configuration list")
                }

                guard
                    let config = configList.buildConfigurations.first(where: {
                        $0.name == configurationName
                    })
                else {
                    throw MCPError.invalidParams(
                        "Configuration '\(configurationName)' not found for target '\(targetName)'")
                }

                // Format build settings
                for (key, value) in config.buildSettings.sorted(by: { $0.key < $1.key }) {
                    let valueString: String
                    switch value {
                    case .string(let str):
                        valueString = str
                    case .array(let arr):
                        valueString = arr.joined(separator: " ")
                    }
                    settingsList.append("  \(key) = \(valueString)")
                }
            case .xcproj(let file):
                guard
                    let target = file.project.targets.first(where: { $0.name == targetName })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                guard
                    let configurationNote = XCProjSupport.configurationNote(
                        for: configurationName, target: target, in: file.project)
                else {
                    throw MCPError.invalidParams(
                        "Configuration '\(configurationName)' not found for target '\(targetName)'")
                }

                settingsList = XCProjSupport.buildSettingLines(of: target)
                note = configurationNote
            }

            let result =
                settingsList.isEmpty
                ? "No build settings found." : settingsList.joined(separator: "\n")

            var message =
                "Build settings for target '\(targetName)' (\(configurationName)):\n\(result)"
            if let note {
                message += "\n\(note)"
            }

            return CallTool.Result(
                content: [
                    .text(message)
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)")
        }
    }
}
