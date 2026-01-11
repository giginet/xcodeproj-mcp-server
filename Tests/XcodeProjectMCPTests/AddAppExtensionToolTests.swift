import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("AddAppExtensionTool Tests")
struct AddAppExtensionToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_app_extension")
        #expect(
            toolDefinition.description
                == "Add an App Extension target to the project and embed it in a host app. Supports Widget, Push Notification, Share, and other extension types."
        )
    }

    @Test("Add app extension with missing parameters")
    func addAppExtensionWithMissingParameters() throws {
        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "extension_name": Value.string("MyWidget"),
                "extension_type": Value.string("widget"),
                "host_target_name": Value.string("TestApp"),
                "bundle_identifier": Value.string("com.test.mywidget"),
            ])
        }

        // Missing extension_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "extension_type": Value.string("widget"),
                "host_target_name": Value.string("TestApp"),
                "bundle_identifier": Value.string("com.test.mywidget"),
            ])
        }

        // Missing extension_type
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "extension_name": Value.string("MyWidget"),
                "host_target_name": Value.string("TestApp"),
                "bundle_identifier": Value.string("com.test.mywidget"),
            ])
        }

        // Missing host_target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "extension_name": Value.string("MyWidget"),
                "extension_type": Value.string("widget"),
                "bundle_identifier": Value.string("com.test.mywidget"),
            ])
        }

        // Missing bundle_identifier
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "extension_name": Value.string("MyWidget"),
                "extension_type": Value.string("widget"),
                "host_target_name": Value.string("TestApp"),
            ])
        }
    }

    @Test("Add widget extension")
    func addWidgetExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created App Extension 'MyWidget'"))
        #expect(message.contains("widget"))
        #expect(message.contains("embedded it in 'TestApp'"))

        // Verify extension target was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let extensionTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "MyWidget" }
        #expect(extensionTarget != nil)
        #expect(extensionTarget?.productType == .appExtension)

        // Verify host target has dependency
        let hostTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        let hasDependency = hostTarget?.dependencies.contains { $0.name == "MyWidget" }
        #expect(hasDependency == true)

        // Verify embed phase exists
        let embedPhase = hostTarget?.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.dstSubfolderSpec == .plugins }
        #expect(embedPhase != nil)
    }

    @Test("Add notification service extension")
    func addNotificationServiceExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("NotificationService"),
            "extension_type": Value.string("notification_service"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.NotificationService"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created App Extension 'NotificationService'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let extensionTarget = xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "NotificationService"
        }
        #expect(extensionTarget != nil)
        #expect(extensionTarget?.productType == .appExtension)
    }

    @Test("Add share extension")
    func addShareExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("ShareExtension"),
            "extension_type": Value.string("share"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.ShareExtension"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created App Extension 'ShareExtension'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let extensionTarget = xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "ShareExtension"
        }
        #expect(extensionTarget != nil)
    }

    @Test("Add extension with deployment target")
    func addExtensionWithDeploymentTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
            "platform": Value.string("iOS"),
            "deployment_target": Value.string("17.0"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created App Extension 'MyWidget'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let extensionTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "MyWidget" }
        let buildConfig = extensionTarget?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        #expect(
            buildConfig?.buildSettings["IPHONEOS_DEPLOYMENT_TARGET"]?.stringValue == "17.0")
    }

    @Test("Add duplicate extension")
    func addDuplicateExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
        ]

        // Add first time
        _ = try tool.execute(arguments: args)

        // Add second time
        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Add extension with non-existent host target")
    func addExtensionWithNonExistentHostTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("NonExistentApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyWidget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Add extension with invalid extension type")
    func addExtensionWithInvalidExtensionType() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyExtension"),
            "extension_type": Value.string("invalid_type"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.MyExtension"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test("Add extension to non-application target")
    func addExtensionToNonApplicationTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create project with framework target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a framework target using AddTargetTool
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("MyFramework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.example.MyFramework"),
        ])

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("MyWidget"),
            "extension_type": Value.string("widget"),
            "host_target_name": Value.string("MyFramework"),
            "bundle_identifier": Value.string("com.example.MyFramework.MyWidget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("is not an application"))
    }

    @Test("Add intents extension")
    func addIntentsExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            component:
                UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddAppExtensionTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "extension_name": Value.string("IntentsExtension"),
            "extension_type": Value.string("intents"),
            "host_target_name": Value.string("TestApp"),
            "bundle_identifier": Value.string("com.example.TestApp.IntentsExtension"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created App Extension 'IntentsExtension'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let extensionTarget = xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "IntentsExtension"
        }
        #expect(extensionTarget != nil)
        #expect(extensionTarget?.productType == .intentsServiceExtension)
    }
}
