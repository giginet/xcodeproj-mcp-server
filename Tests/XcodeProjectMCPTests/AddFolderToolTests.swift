import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

struct AddFolderToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        self.tempDir =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("AddFolderToolTests-\(UUID().uuidString)")
            .path
        self.pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test("Tool has correct properties")
    func toolProperties() {
        let tool = AddFolderTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_synchronized_folder")
        #expect(
            tool.tool().description == "Add a synchronized folder reference to an Xcode project")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["group_name"] != nil)
                #expect(props["target_name"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 2)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("folder_path")))
            }
        }
    }

    @Test("Validates required parameters")
    func validateRequiredParameters() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["folder_path": .string("path/to/folder")])
        }

        // Missing folder_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("project.xcodeproj")])
        }

        // Invalid parameter types
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.bool(true),
                "folder_path": Value.string("path/to/folder"),
            ])
        }
    }

    @Test("Adds folder reference to project")
    func addsFolderToProject() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(folderPath.string),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the project was updated
        let updatedProject = try XcodeProj(path: projectPath)
        let folderReferences = updatedProject.pbxproj.fileSystemSynchronizedRootGroups
        #expect(folderReferences.count == 1)
        #expect(folderReferences.first?.name == "TestFolder")
    }

    @Test("Adds folder to specific group")
    func addsFolderToSpecificGroup() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Load the project and add a custom group
        let xcodeproj = try XcodeProj(path: projectPath)
        let customGroup = PBXGroup(children: [], sourceTree: .group, name: "CustomGroup")
        xcodeproj.pbxproj.add(object: customGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(customGroup)
        }
        try xcodeproj.write(path: projectPath)

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(folderPath.string),
            "group_name": .string("CustomGroup"),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
            #expect(message.contains("in group 'CustomGroup'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the folder was added to the correct group
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedCustomGroup = updatedProject.pbxproj.groups.first { $0.name == "CustomGroup" }
        #expect(updatedCustomGroup?.children.count == 1)
    }

    @Test("Adds folder to target")
    func addsFolderToTarget() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project with a target
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestTarget", at: projectPath)

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "folder_path": Value.string(folderPath.string),
            "target_name": Value.string("TestTarget"),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
            #expect(message.contains("to target 'TestTarget'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the folder was added to the target
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedTarget = updatedProject.pbxproj.nativeTargets.first { $0.name == "TestTarget" }
        let resourcesPhase = updatedTarget?.buildPhases.first { $0 is PBXResourcesBuildPhase }
        #expect(resourcesPhase != nil)
    }

    @Test("Fails when folder does not exist")
    func failsWhenFolderDoesNotExist() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Try to add a non-existent folder
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("/path/that/does/not/exist"),
            ])
        }

        // Clean up
        try FileManager.default.removeItem(atPath: projectPath.string)
    }

    @Test("Fails when path is not a directory")
    func failsWhenPathIsNotDirectory() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a file instead of a folder
        let filePath = Path(tempDir) + "TestFile.txt"
        try "test content".write(
            to: URL(filePath: filePath.string), atomically: true, encoding: .utf8)

        // Try to add a file as a folder
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string(filePath.string),
            ])
        }

        // Clean up
        try FileManager.default.removeItem(atPath: projectPath.string)
        try FileManager.default.removeItem(atPath: filePath.string)
    }
}
