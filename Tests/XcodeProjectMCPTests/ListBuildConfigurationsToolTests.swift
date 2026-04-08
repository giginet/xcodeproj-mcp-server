import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

struct ListBuildConfigurationsToolTests {

    @Test func testListBuildConfigurationsToolCreation() {
        let tool = ListBuildConfigurationsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_build_configurations")
        #expect(toolDefinition.description == "List all build configurations in an Xcode project")
    }

    @Test func testListBuildConfigurationsWithMissingProjectPath() throws {
        let tool = ListBuildConfigurationsTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test func testListBuildConfigurationsWithInvalidProjectPath() throws {
        let tool = ListBuildConfigurationsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj")
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func testListBuildConfigurationsWithValidProject() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListBuildConfigurationsTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // List build configurations in the created project
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string)
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("TestProject.xcodeproj"))
            #expect(content.contains("Debug") || content.contains("Release"))
        } else {
            Issue.record("Expected text content")
        }
    }
}
