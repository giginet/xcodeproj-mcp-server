import Testing
import Foundation
import MCP
import XcodeProj
import PathKit
@testable import XcodeProjectMCP

@Suite("AddFrameworkTool Tests")
struct AddFrameworkToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddFrameworkTool()
        let toolDefinition = tool.tool()
        
        #expect(toolDefinition.name == "add_framework")
        #expect(toolDefinition.description == "Add framework dependencies")
    }
    
    @Test("Add framework with missing parameters")
    func addFrameworkWithMissingParameters() throws {
        let tool = AddFrameworkTool()
        
        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": .string("App"),
                "framework_name": .string("UIKit")
            ])
        }
        
        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path/to/project.xcodeproj"),
                "framework_name": .string("UIKit")
            ])
        }
        
        // Missing framework_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path/to/project.xcodeproj"),
                "target_name": .string("App")
            ])
        }
    }
    
    @Test("Add system framework")
    func addSystemFramework() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(name: "TestProject", targetName: "App", at: projectPath)
        
        // Add system framework
        let tool = AddFrameworkTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "framework_name": .string("UIKit")
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework 'UIKit'"))
        
        // Verify framework was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let frameworkPhase = target?.buildPhases.first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
        
        let hasUIKit = frameworkPhase?.files?.contains { buildFile in
            if let fileRef = buildFile.file as? PBXFileReference {
                return fileRef.name == "UIKit.framework"
            }
            return false
        } ?? false
        
        #expect(hasUIKit == true)
    }
    
    @Test("Add custom framework without embedding")
    func addCustomFrameworkWithoutEmbedding() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(name: "TestProject", targetName: "App", at: projectPath)
        
        // Add custom framework
        let tool = AddFrameworkTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "framework_name": .string("../Frameworks/Custom.framework"),
            "embed": .bool(false)
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(!message.contains("(embedded)"))
    }
    
    @Test("Add custom framework with embedding")
    func addCustomFrameworkWithEmbedding() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(name: "TestProject", targetName: "App", at: projectPath)
        
        // Add custom framework with embedding
        let tool = AddFrameworkTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "framework_name": .string("../Frameworks/Custom.framework"),
            "embed": .bool(true)
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(message.contains("(embedded)"))
        
        // Verify embed frameworks phase was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        
        let hasEmbedPhase = target?.buildPhases.contains { phase in
            if let copyPhase = phase as? PBXCopyFilesBuildPhase {
                return copyPhase.dstSubfolderSpec == .frameworks
            }
            return false
        } ?? false
        
        #expect(hasEmbedPhase == true)
    }
    
    @Test("Add duplicate framework")
    func addDuplicateFramework() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(name: "TestProject", targetName: "App", at: projectPath)
        
        let tool = AddFrameworkTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "framework_name": .string("UIKit")
        ]
        
        // Add framework first time
        _ = try tool.execute(arguments: args)
        
        // Try to add again
        let result = try tool.execute(arguments: args)
        
        // Check the result contains already exists message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }
    
    @Test("Add framework to non-existent target")
    func addFrameworkToNonExistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        
        let tool = AddFrameworkTool()
        let args: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistentTarget"),
            "framework_name": .string("UIKit")
        ]
        
        let result = try tool.execute(arguments: args)
        
        // Check the result contains not found message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}