import Testing
import Foundation
import MCP
import XcodeProj
import PathKit
@testable import XcodeProjectMCP

@Suite("CreateGroupTool Tests")
struct CreateGroupToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = CreateGroupTool()
        let toolDefinition = tool.tool()
        
        #expect(toolDefinition.name == "create_group")
        #expect(toolDefinition.description == "Create a new group in the project navigator")
    }
    
    @Test("Create group with missing project path")
    func createGroupWithMissingProjectPath() throws {
        let tool = CreateGroupTool()
        
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["group_name": .string("NewGroup")])
        }
    }
    
    @Test("Create group with missing group name")
    func createGroupWithMissingGroupName() throws {
        let tool = CreateGroupTool()
        
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path/to/project.xcodeproj")])
        }
    }
    
    @Test("Create group in main group")
    func createGroupInMainGroup() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = CreateGroupTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("NewGroup")
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = CreateGroupTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("Sources"),
            "path": .string("Sources")
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = CreateGroupTool()
        
        // First create a parent group
        let parentArgs: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("ParentGroup")
        ]
        _ = try tool.execute(arguments: parentArgs)
        
        // Then create a child group
        let childArgs: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("ChildGroup"),
            "parent_group": .string("ParentGroup")
        ]
        
        let result = try tool.execute(arguments: childArgs)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'ChildGroup' in ParentGroup"))
        
        // Verify group hierarchy
        let xcodeproj = try XcodeProj(path: projectPath)
        let parentGroup = xcodeproj.pbxproj.groups.first { $0.name == "ParentGroup" }
        #expect(parentGroup != nil)
        
        let childInParent = parentGroup?.children.contains { element in
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = CreateGroupTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("MyGroup")
        ]
        
        // Create group first time
        _ = try tool.execute(arguments: args)
        
        // Try to create again
        let result = try tool.execute(arguments: args)
        
        // Check the result contains already exists message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }
    
    @Test("Create group with non-existent parent")
    func createGroupWithNonExistentParent() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = CreateGroupTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "group_name": .string("NewGroup"),
            "parent_group": .string("NonExistentGroup")
        ]
        
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}