import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("DuplicateTargetTool Tests")
struct DuplicateTargetToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "duplicate_target")
        #expect(toolDefinition.description == "Duplicate an existing target")
    }

    @Test("Duplicate target with missing parameters")
    func duplicateTargetWithMissingParameters() throws {
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "source_target": Value.string("App"),
                "new_target_name": Value.string("AppCopy"),
            ])
        }

        // Missing source_target
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_target_name": Value.string("AppCopy"),
            ])
        }

        // Missing new_target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "source_target": Value.string("App"),
            ])
        }
    }

    @Test("Duplicate existing target")
    func duplicateExistingTarget() throws {
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
            name: "TestProject", targetName: "App", at: projectPath)

        // Duplicate the target
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "source_target": Value.string("App"),
            "new_target_name": Value.string("AppDev"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully duplicated target 'App' as 'AppDev'"))

        // Verify new target was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let newTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppDev" }
        #expect(newTarget != nil)

        // Verify it has the same product type as source
        let sourceTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(newTarget?.productType == sourceTarget?.productType)

        // Verify it has build phases
        #expect(newTarget?.buildPhases.isEmpty == false)
    }

    @Test("Duplicate target with new bundle identifier")
    func duplicateTargetWithNewBundleIdentifier() throws {
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
            name: "TestProject", targetName: "App", at: projectPath)

        // Duplicate the target with new bundle identifier
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "source_target": Value.string("App"),
            "new_target_name": Value.string("AppStaging"),
            "new_bundle_identifier": Value.string("com.test.app.staging"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully duplicated target"))
        #expect(message.contains("with bundle identifier 'com.test.app.staging'"))

        // Verify bundle identifier was updated
        let xcodeproj = try XcodeProj(path: projectPath)
        let newTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppStaging" }
        let buildConfig = newTarget?.buildConfigurationList?.buildConfigurations.first
        #expect(
            buildConfig?.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.test.app.staging")
        #expect(buildConfig?.buildSettings["PRODUCT_NAME"]?.stringValue == "AppStaging")
    }

    @Test("Duplicate non-existent target")
    func duplicateNonExistentTarget() throws {
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

        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "source_target": Value.string("NonExistentTarget"),
            "new_target_name": Value.string("NewTarget"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Duplicate to existing target name")
    func duplicateToExistingTargetName() throws {
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
            name: "TestProject", targetName: "App", at: projectPath)

        // Add another target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("ExistingTarget"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.existing"),
        ])

        // Try to duplicate to existing name
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "source_target": Value.string("App"),
            "new_target_name": Value.string("ExistingTarget"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Duplicate target with dependencies")
    func duplicateTargetWithDependencies() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with targets
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ])

        // Add dependency
        let addDependencyTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addDependencyTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ])

        // Duplicate the target
        let tool = DuplicateTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "source_target": Value.string("App"),
            "new_target_name": Value.string("AppCopy"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully duplicated"))

        // Verify dependencies were copied
        let xcodeproj = try XcodeProj(path: projectPath)
        let newTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppCopy" }
        let hasDependency = newTarget?.dependencies.contains { $0.name == "Framework" } ?? false
        #expect(hasDependency == true)
    }
}
