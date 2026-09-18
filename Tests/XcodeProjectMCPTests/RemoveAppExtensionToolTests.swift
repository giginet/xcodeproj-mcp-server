import Foundation
import MCP
import PathKit
import Testing
import XcodeProj
import XcodeProjectFormat

@testable import XcodeProjectMCP

@Suite("RemoveAppExtensionTool Tests", .temporaryDirectory)
struct RemoveAppExtensionToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_app_extension")
        #expect(
            toolDefinition.description
                == "Remove an App Extension target from the project and its embedding from the host app"
        )
    }

    @Test("Remove app extension with missing parameters")
    func removeAppExtensionWithMissingParameters() throws {
        let tool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "extension_name": Value.string("MyWidget")
            ])
        }

        // Missing extension_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj")
            ])
        }
    }

    @Test("Remove widget extension")
    func removeWidgetExtension() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // First add an extension
        let addTool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
        ])

        // Verify extension was added
        var xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "MyWidget" })

        // Now remove the extension
        let removeTool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed App Extension 'MyWidget'"))

        // Verify extension was removed
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(!xcodeproj.pbxproj.nativeTargets.contains { $0.name == "MyWidget" })

        // Verify host target no longer has dependency
        let hostTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        let hasDependency = hostTarget?.dependencies.contains { $0.name == "MyWidget" }
        #expect(hasDependency != true)
    }

    @Test("Remove non-existent extension")
    func removeNonExistentExtension() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let removeTool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("NonExistentWidget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Remove non-extension target fails")
    func removeNonExtensionTargetFails() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let removeTool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("TestApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("is not an App Extension"))
    }

    @Test("Remove extension cleans up embed phase")
    func removeExtensionCleansUpEmbedPhase() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Add an extension
        let addTool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
        ])

        // Remove the extension
        let removeTool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
        ])

        // Verify embed phase is empty or removed
        let xcodeproj = try XcodeProj(path: projectPath)
        let hostTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        let embedPhase = hostTarget?.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Embed App Extensions" }

        // Either the phase should be removed or it should have no files
        if let embedPhase = embedPhase {
            #expect(embedPhase.files?.isEmpty == true)
        }
    }

    @Test("Remove multiple extensions")
    func removeMultipleExtensions() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Add two extensions
        let addTool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))

        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("Widget1"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.Widget1"),
        ])

        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("Widget2"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.Widget2"),
        ])

        // Verify both were added
        var xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Widget1" })
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Widget2" })

        // Remove first extension
        let removeTool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("Widget1"),
        ])

        // Verify first was removed but second remains
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(!xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Widget1" })
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Widget2" })

        // Remove second extension
        _ = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("Widget2"),
        ])

        // Verify second was removed
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(!xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Widget2" })
    }

    @Test("Remove widget extension from xcproj project")
    func removeWidgetExtensionFromXCProjProject() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let pathUtility = PathUtility(basePath: tempDir.path)
        _ = try AddAppExtensionTool(pathUtility: pathUtility).execute(arguments: [
            "project_path": .string(projectPath.string),
            "extension_name": .string("MyWidget"),
            "extension_type": .string("widget"),
            "host_target_name": .string("TestApp"),
            "bundle_identifier": .string("com.example.TestApp.MyWidget"),
        ])

        let tool = RemoveAppExtensionTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "extension_name": .string("MyWidget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed App Extension 'MyWidget'"))

        let file = try XCProjFile.load(bundleURL: URL(fileURLWithPath: projectPath.string))
        #expect(file.project.targets.contains(where: { $0.name == "MyWidget" }) == false)

        // Host no longer depends on it, the empty embed phase is cleaned up,
        // and the product reference is gone
        let host = file.project.targets.first(where: { $0.name == "TestApp" })
        #expect(host?.commonProperties.dependencies.isEmpty == true)
        let hasEmbedPhase = host?.commonProperties.buildPhases.contains { phase in
            if case .copy = phase { return true }
            return false
        }
        #expect(hasEmbedPhase == false)
        var productFound = false
        XCProjTreeEditor.forEachFileReference(in: file.project.topLevelReferences) {
            fileReference in
            if fileReference.path.stringRepresentation.hasSuffix("MyWidget.appex") {
                productFound = true
            }
        }
        #expect(productFound == false)
    }

    @Test("Remove app extension rejects non-extension target in xcproj project")
    func removeAppExtensionRejectsNonExtensionInXCProjProject() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = RemoveAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "extension_name": .string("TestApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("is not an App Extension"))
    }
}
