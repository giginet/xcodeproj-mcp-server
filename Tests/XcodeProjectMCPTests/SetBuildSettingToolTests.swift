import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("SetBuildSettingTool Tests")
struct SetBuildSettingToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_build_setting")
        #expect(toolDefinition.description == "Modify build settings for a target")
    }

    @Test("Set build setting with missing parameters")
    func setBuildSettingWithMissingParameters() throws {
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ])
        }

        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ])
        }

        // Missing configuration
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ])
        }

        // Missing setting_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_value": Value.string("5.0"),
            ])
        }

        // Missing setting_value
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
            ])
        }
    }

    @Test("Set build setting for specific configuration")
    func setBuildSettingForSpecificConfiguration() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Set build setting
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully set 'SWIFT_VERSION' to '5.9'"))
        #expect(message.contains("Debug"))

        // Verify setting was changed
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let debugConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        #expect(debugConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")

        // Verify Release config was not changed
        let releaseConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Release"
        }
        #expect(releaseConfig?.buildSettings["SWIFT_VERSION"]?.stringValue != "5.9")
    }

    @Test("Set build setting for all configurations")
    func setBuildSettingForAllConfigurations() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Set build setting for all configurations
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("All"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully set 'SWIFT_VERSION' to '5.9'"))
        #expect(message.contains("Debug"))
        #expect(message.contains("Release"))

        // Verify setting was changed in all configurations
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let debugConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        let releaseConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Release"
        }

        #expect(debugConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")
        #expect(releaseConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")
    }

    @Test("Set build setting with non-existent target")
    func setBuildSettingWithNonExistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Set build setting with non-existent configuration")
    func setBuildSettingWithNonExistentConfiguration() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Production"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Configuration 'Production' not found"))
    }
}
