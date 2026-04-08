import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

struct GetBuildSettingsToolTests {

    @Test func testGetBuildSettingsToolCreation() {
        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "get_build_settings")
        #expect(
            toolDefinition.description
                == "Get build settings for a specific target in an Xcode project")
    }

    @Test func testGetBuildSettingsWithMissingProjectPath() throws {
        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["target_name": Value.string("TestTarget")])
        }
    }

    @Test func testGetBuildSettingsWithMissingTargetName() throws {
        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("/path/to/project.xcodeproj")]
            )
        }
    }

    @Test func testGetBuildSettingsWithInvalidProjectPath() throws {
        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
            "target_name": Value.string("TestTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func testGetBuildSettingsWithNonexistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Try to get build settings for non-existent target
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonexistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func testGetBuildSettingsWithValidTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with a target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Get build settings
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestApp"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Build settings for target 'TestApp'"))
            #expect(content.contains("PRODUCT_NAME") || content.contains("BUNDLE_IDENTIFIER"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testGetBuildSettingsWithSpecificConfiguration() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = GetBuildSettingsTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with a target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Get build settings for Release configuration
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestApp"),
            "configuration": Value.string("Release"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Build settings for target 'TestApp' (Release)"))
        } else {
            Issue.record("Expected text content")
        }
    }
}
