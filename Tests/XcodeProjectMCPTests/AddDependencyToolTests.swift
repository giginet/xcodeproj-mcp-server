import Foundation
import MCP
import PathKit
import Testing
import XcodeProj
import XcodeProjectFormat

@testable import XcodeProjectMCP

@Suite("AddDependencyTool Tests", .temporaryDirectory)
struct AddDependencyToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_dependency")
        #expect(
            toolDefinition.description
                == "Add dependency between targets"
        )
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
        let tempDir = TemporaryDirectory.url

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
        let tempDir = TemporaryDirectory.url

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
        let tempDir = TemporaryDirectory.url

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
        let tempDir = TemporaryDirectory.url

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

    @Test("Add dependency in xcproj project")
    func addDependencyInXCProjProject() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)
        _ = try AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path)).execute(
            arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("Kit"),
                "product_type": .string("framework"),
                "bundle_identifier": .string("com.example.kit"),
            ])

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Kit"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added dependency 'Kit'"))

        let file = try XCProjFile.load(bundleURL: URL(fileURLWithPath: projectPath.string))
        let app = file.project.targets.first(where: { $0.name == "App" })
        let hasDependency = app?.commonProperties.dependencies.contains { dependency in
            if case .localTarget(let reference, _) = dependency {
                return reference.targetName == "Kit"
            }
            return false
        }
        #expect(hasDependency == true)

        // Adding it again reports the duplicate
        let second = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Kit"),
        ])
        guard case let .text(secondMessage, _, _) = second.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(secondMessage.contains("already depends"))
    }
}
