import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("AddDependencyTool Tests")
struct AddDependencyToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_dependency")
        #expect(toolDefinition.description == "Add dependency between targets")
    }

    @Test("Add dependency with missing parameters")
    func addDependencyWithMissingParameters() throws {
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "dependency_name": Value.string("Framework"),
            ])
        }

        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "dependency_name": Value.string("Framework"),
            ])
        }

        // Missing dependency_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }
    }

    @Test("Add dependency between targets")
    func addDependencyBetweenTargets() throws {
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

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addFrameworkArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTargetTool.execute(arguments: addFrameworkArgs)

        // Add dependency
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added dependency 'Framework' to target 'App'"))

        // Verify dependency was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(appTarget != nil)

        let hasDependency =
            appTarget?.dependencies.contains { dependency in
                dependency.name == "Framework"
            } ?? false
        #expect(hasDependency == true)
    }

    @Test("Add duplicate dependency")
    func addDuplicateDependency() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with targets
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addFrameworkArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTargetTool.execute(arguments: addFrameworkArgs)

        // Add dependency
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ]

        _ = try tool.execute(arguments: args)

        // Try to add the same dependency again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already depends on"))
    }

    @Test("Add dependency with non-existent target")
    func addDependencyWithNonExistentTarget() throws {
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

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "dependency_name": Value.string("Framework"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Add dependency with non-existent dependency")
    func addDependencyWithNonExistentDependency() throws {
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

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("NonExistentFramework"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}
