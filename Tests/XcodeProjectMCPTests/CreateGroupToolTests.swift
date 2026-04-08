import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("CreateGroupTool Tests")
struct CreateGroupToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "create_group")
        #expect(toolDefinition.description == "Create a new group in the project navigator")
    }

    @Test("Create group with missing project path")
    func createGroupWithMissingProjectPath() throws {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["group_name": Value.string("NewGroup")])
        }
    }

    @Test("Create group with missing group name")
    func createGroupWithMissingGroupName() throws {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("/path/to/project.xcodeproj")]
            )
        }
    }

    @Test("Create group in main group")
    func createGroupInMainGroup() throws {
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

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("NewGroup"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'NewGroup'"))
        #expect(message.contains("main group"))

        // Verify group was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let groups = xcodeproj.pbxproj.groups
        let newGroup = groups.first { $0.name == "NewGroup" }
        #expect(newGroup != nil)
    }

    @Test("Create group with path")
    func createGroupWithPath() throws {
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

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("Sources"),
            "path": Value.string("Sources"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'Sources'"))

        // Verify group was created with path
        let xcodeproj = try XcodeProj(path: projectPath)
        let groups = xcodeproj.pbxproj.groups
        let sourcesGroup = groups.first { $0.name == "Sources" }
        #expect(sourcesGroup != nil)
        #expect(sourcesGroup?.path == "Sources")
    }

    @Test("Create group in parent group")
    func createGroupInParentGroup() throws {
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

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))

        // First create a parent group
        let parentArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
        ]
        _ = try tool.execute(arguments: parentArgs)

        // Then create a child group
        let childArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ChildGroup"),
            "parent_group": Value.string("ParentGroup"),
        ]

        let result = try tool.execute(arguments: childArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'ChildGroup' in ParentGroup"))

        // Verify group hierarchy
        let xcodeproj = try XcodeProj(path: projectPath)
        let parentGroup = xcodeproj.pbxproj.groups.first { $0.name == "ParentGroup" }
        #expect(parentGroup != nil)

        let childInParent =
            parentGroup?.children.contains { element in
                if let group = element as? PBXGroup {
                    return group.name == "ChildGroup"
                }
                return false
            } ?? false
        #expect(childInParent == true)
    }

    @Test("Create duplicate group")
    func createDuplicateGroup() throws {
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

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("MyGroup"),
        ]

        // Create group first time
        _ = try tool.execute(arguments: args)

        // Try to create again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Create group in nested parent group using hierarchical path")
    func createGroupInNestedParentGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithNestedGroups(
            name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Create a group using hierarchical parent path "TopLevel/Nested"
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("NewChild"),
            "parent_group": Value.string("TopLevel/Nested"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'NewChild'"))

        // Verify NewChild was added to the "Nested" group
        let xcodeproj = try XcodeProj(path: projectPath)
        let nestedGroup = xcodeproj.pbxproj.groups.first { $0.name == "Nested" }
        #expect(nestedGroup != nil)
        let newChild = nestedGroup?.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "NewChild"
        }
        #expect(newChild != nil)
    }

    @Test("Create group with non-existent parent")
    func createGroupWithNonExistentParent() throws {
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

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("NewGroup"),
            "parent_group": Value.string("NonExistentGroup"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
