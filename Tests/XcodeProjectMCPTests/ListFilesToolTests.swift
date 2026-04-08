import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

struct ListFilesToolTests {

    @Test func testListFilesToolCreation() {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_files")
        #expect(
            toolDefinition.description == "List all files in a specific target of an Xcode project")
    }

    @Test func testListFilesWithMissingParameters() throws {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("test.xcodeproj")])
        }
    }

    @Test func testListFilesWithInvalidProjectPath() throws {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
            "target_name": Value.string("TestTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func testListFilesWithEmptyTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath)

        // List files in the target
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("TestProject"))
            #expect(content.contains("No files found"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testListFilesWithInvalidTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath)

        // List files with invalid target name
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: listArguments)
        }
    }

    @Test func testListFilesWithSourceFiles() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath)

        // Add a source file to the project
        let sourceFilePath = tempDir.path + "/TestFile.swift"
        try "// Test file content".write(
            to: URL(filePath: sourceFilePath), atomically: true, encoding: .utf8)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first!
        let fileReference = PBXFileReference(
            sourceTree: .group, name: "TestFile.swift", path: "TestFile.swift")
        xcodeproj.pbxproj.add(object: fileReference)

        let buildFile = PBXBuildFile(file: fileReference)
        xcodeproj.pbxproj.add(object: buildFile)

        if let sourcesBuildPhase = target.buildPhases.first(where: { $0 is PBXSourcesBuildPhase })
            as? PBXSourcesBuildPhase
        {
            sourcesBuildPhase.files?.append(buildFile)
        }

        try xcodeproj.write(path: projectPath)

        // List files in the target
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("TestFile.swift"))
        } else {
            Issue.record("Expected text content")
        }
    }
}
