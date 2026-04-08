import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("MoveFileTool Tests")
struct MoveFileToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "move_file")
        #expect(toolDefinition.description == "Move or rename a file within the project")
    }

    @Test("Move file with missing project path")
    func moveFileWithMissingProjectPath() throws {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: [
                    "old_path": Value.string("old.swift"),
                    "new_path": Value.string("new.swift"),
                ] as [String: Value])
        }
    }

    @Test("Move file with missing old path")
    func moveFileWithMissingOldPath() throws {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: [
                    "project_path": Value.string("/path/to/project.xcodeproj"),
                    "new_path": Value.string("new.swift"),
                ] as [String: Value])
        }
    }

    @Test("Move file with missing new path")
    func moveFileWithMissingNewPath() throws {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: [
                    "project_path": Value.string("/path/to/project.xcodeproj"),
                    "old_path": Value.string("old.swift"),
                ] as [String: Value])
        }
    }

    @Test("Move file in project")
    func moveFile() throws {
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
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // First add a file to move
        let addTool = AddFileTool(pathUtility: PathUtility(basePath: "/"))
        let oldFilePath = tempDir.appendingPathComponent("OldFile.swift").path
        try "// Test file".write(toFile: oldFilePath, atomically: true, encoding: .utf8)

        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(oldFilePath),
            "target_name": Value.string("TestApp"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Now move the file
        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let newFilePath = tempDir.appendingPathComponent("NewFile.swift").path
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string(oldFilePath),
            "new_path": Value.string(newFilePath),
            "move_on_disk": Value.bool(false),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully moved"))

        // Verify file was moved in project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences

        // Check that old path doesn't exist
        let oldFileExists = fileReferences.contains {
            $0.path == oldFilePath || $0.name == "OldFile.swift"
        }
        #expect(oldFileExists == false)

        // Check that new path exists
        let newFileExists = fileReferences.contains {
            $0.path == newFilePath || $0.name == "NewFile.swift"
        }
        #expect(newFileExists == true)

        // Verify file still exists at old path on disk (move_on_disk was false)
        #expect(FileManager.default.fileExists(atPath: oldFilePath) == true)
        #expect(FileManager.default.fileExists(atPath: newFilePath) == false)
    }

    @Test("Move file on disk")
    func moveFileOnDisk() throws {
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
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // First add a file to move
        let addTool = AddFileTool(pathUtility: PathUtility(basePath: "/"))
        let oldFilePath = tempDir.appendingPathComponent("OldFile.swift").path
        try "// Test file".write(toFile: oldFilePath, atomically: true, encoding: .utf8)

        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(oldFilePath),
            "target_name": Value.string("TestApp"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Now move the file with move_on_disk = true
        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let newFilePath = tempDir.appendingPathComponent("subfolder/NewFile.swift").path
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string(oldFilePath),
            "new_path": Value.string(newFilePath),
            "move_on_disk": Value.bool(true),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully moved"))

        // Verify file was moved on disk
        #expect(FileManager.default.fileExists(atPath: oldFilePath) == false)
        #expect(FileManager.default.fileExists(atPath: newFilePath) == true)

        // Verify content is preserved
        let content = try String(contentsOfFile: newFilePath)
        #expect(content == "// Test file")
    }

    @Test("Move non-existent file")
    func moveNonExistentFile() throws {
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

        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string("/path/to/nonexistent.swift"),
            "new_path": Value.string("/path/to/new.swift"),
            "move_on_disk": Value.bool(false),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("File not found"))
    }
}
