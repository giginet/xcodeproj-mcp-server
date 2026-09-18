import Foundation
import MCP
import PathKit
import Testing
import XcodeProj
import XcodeProjectFormat

@testable import XcodeProjectMCP

@Suite("AddFrameworkTool Tests", .temporaryDirectory)
struct AddFrameworkToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_framework")
        #expect(
            toolDefinition.description
                == "Add framework dependencies"
        )
    }

    @Test("Add framework with missing parameters")
    func addFrameworkWithMissingParameters() throws {
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "framework_name": Value.string("UIKit"),
            ])
        }

        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "framework_name": Value.string("UIKit"),
            ])
        }

        // Missing framework_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }
    }

    @Test("Add system framework")
    func addSystemFramework() throws {
        let tempDir = TemporaryDirectory.url

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add system framework
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework 'UIKit'"))

        // Verify framework was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let frameworkPhase =
            target?.buildPhases.first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

        let hasUIKit =
            frameworkPhase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "UIKit.framework"
                }
                return false
            } ?? false

        #expect(hasUIKit == true)
    }

    @Test("Add custom framework without embedding")
    func addCustomFrameworkWithoutEmbedding() throws {
        let tempDir = TemporaryDirectory.url

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add custom framework
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string(tempDir.appendingPathComponent("Custom.framework").path),
            "embed": Value.bool(false),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(!message.contains("(embedded)"))
    }

    @Test("Add custom framework with embedding")
    func addCustomFrameworkWithEmbedding() throws {
        let tempDir = TemporaryDirectory.url

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add custom framework with embedding
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string(tempDir.appendingPathComponent("Custom.framework").path),
            "embed": Value.bool(true),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(message.contains("(embedded)"))

        // Verify embed frameworks phase was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }

        let hasEmbedPhase =
            target?.buildPhases.contains { phase in
                if let copyPhase = phase as? PBXCopyFilesBuildPhase {
                    return copyPhase.dstSubfolderSpec == .frameworks
                }
                return false
            } ?? false

        #expect(hasEmbedPhase == true)
    }

    @Test("Add duplicate framework")
    func addDuplicateFramework() throws {
        let tempDir = TemporaryDirectory.url

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ]

        // Add framework first time
        _ = try tool.execute(arguments: args)

        // Try to add again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Add framework to non-existent target")
    func addFrameworkToNonExistentTarget() throws {
        let tempDir = TemporaryDirectory.url

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "framework_name": Value.string("UIKit"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Add system framework in xcproj project")
    func addSystemFrameworkInXCProjProject() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("TestApp"),
            "framework_name": .string("UIKit"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework 'UIKit'"))

        let file = try XCProjFile.load(bundleURL: URL(fileURLWithPath: projectPath.string))
        // The framework file reference lives in a "Frameworks" group and is
        // linked into the target's frameworks phase
        var found = false
        XCProjTreeEditor.forEachFileReference(in: file.project.topLevelReferences) {
            fileReference in
            if fileReference.path.stringRepresentation.hasSuffix("UIKit.framework"),
                !fileReference.buildFiles.isEmpty
            {
                found = true
            }
        }
        #expect(found)

        // Adding it again reports the duplicate
        let second = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("TestApp"),
            "framework_name": .string("UIKit"),
        ])
        guard case let .text(secondMessage, _, _) = second.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(secondMessage.contains("already exists"))
    }
}
