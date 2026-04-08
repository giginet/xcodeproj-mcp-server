import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

struct AddFileToolTests {

    @Test func testAddFileToolCreation() {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_file")
        #expect(toolDefinition.description == "Add a file to an Xcode project")
    }

    @Test func testAddFileWithMissingProjectPath() throws {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["file_path": Value.string("test.swift")])
        }
    }

    @Test func testAddFileWithMissingFilePath() throws {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("/path/to/project.xcodeproj")]
            )
        }
    }

    @Test func testAddFileWithInvalidProjectPath() throws {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
            "file_path": Value.string("test.swift"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func testAddFileToMainGroup() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a file
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)
    }

    @Test func testAddFileToGroup() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a file to "Tests" group
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "group_name": Value.string("Tests"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)
    }

    @Test func testAddFileToTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with a target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Add a Swift file to target
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "target_name": Value.string("TestApp"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift' to target 'TestApp'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project and target
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)

        // Verify file was added to target's sources build phase
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil)

        let sourcesBuildPhase =
            target?.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)

        let buildFile = sourcesBuildPhase?.files?.first { $0.file == addedFile }
        #expect(buildFile != nil)
    }

    @Test func testAddFileWithNonexistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Try to add file to non-existent target
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "target_name": Value.string("NonexistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }
}
