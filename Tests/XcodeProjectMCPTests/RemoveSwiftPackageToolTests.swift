import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("RemoveSwiftPackageTool Tests")
struct RemoveSwiftPackageToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_swift_package")
        #expect(
            toolDefinition.description == "Remove a Swift Package dependency from an Xcode project")
    }

    @Test("Remove package with missing parameters")
    func removePackageWithMissingParameters() throws {
        let tool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "package_url": Value.string("https://github.com/alamofire/alamofire.git")
            ])
        }

        // Missing package_url
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj")
            ])
        }
    }

    @Test("Remove non-existent package")
    func removeNonExistentPackage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/nonexistent/package.git"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found in project"))
    }

    @Test("Remove existing package from project")
    func removeExistingPackageFromProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // First add a package
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
            "requirement": Value.string("5.0.0"),
        ])

        // Verify package was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        #expect(project?.remotePackages.count == 1)

        // Now remove the package
        let removeTool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
        ]

        let result = try removeTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed Swift Package"))
        #expect(message.contains("alamofire"))

        // Verify package was removed
        let updatedXcodeproj = try XcodeProj(path: projectPath)
        let updatedProject = try updatedXcodeproj.pbxproj.rootProject()
        #expect(updatedProject?.remotePackages.count == 0)
    }

    @Test("Remove package from project and targets")
    func removePackageFromProjectAndTargets() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Add a package to a specific target
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/rxswift/rxswift.git"),
            "requirement": Value.string("6.0.0"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("RxSwift"),
        ])

        // Verify package and dependency were added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }

        #expect(project?.remotePackages.count == 1)
        #expect(target?.packageProductDependencies?.count == 1)

        // Remove the package (should remove from targets by default)
        let removeTool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/rxswift/rxswift.git"),
            "remove_from_targets": Value.bool(true),
        ]

        let result = try removeTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed Swift Package"))
        #expect(message.contains("and all targets"))

        // Verify package and dependencies were removed
        let updatedXcodeproj = try XcodeProj(path: projectPath)
        let updatedProject = try updatedXcodeproj.pbxproj.rootProject()
        let updatedTarget = updatedXcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }

        #expect(updatedProject?.remotePackages.count == 0)
        #expect(updatedTarget?.packageProductDependencies?.count == 0)
    }

    @Test("Remove package but keep target dependencies")
    func removePackageButKeepTargetDependencies() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        // Add a package to a specific target
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string(
                "https://github.com/pointfreeco/swift-composable-architecture.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("ComposableArchitecture"),
        ])

        // Remove the package but keep target dependencies
        let removeTool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string(
                "https://github.com/pointfreeco/swift-composable-architecture.git"),
            "remove_from_targets": Value.bool(false),
        ]

        let result = try removeTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed Swift Package"))
        #expect(!message.contains("and all targets"))

        // Verify package was removed but dependencies remain (though they may be broken)
        let updatedXcodeproj = try XcodeProj(path: projectPath)
        let updatedProject = try updatedXcodeproj.pbxproj.rootProject()
        let updatedTarget = updatedXcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }

        #expect(updatedProject?.remotePackages.count == 0)
        // Note: Target dependencies may still exist but will be broken since package reference is gone
        #expect(updatedTarget?.packageProductDependencies?.count == 1)
    }

    @Test("Remove multiple packages")
    func removeMultiplePackages() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add multiple packages
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
            "requirement": Value.string("5.0.0"),
        ])

        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
        ])

        // Verify both packages were added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        #expect(project?.remotePackages.count == 2)

        // Remove one package
        let removeTool = RemoveSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
        ])

        // Verify only one package remains
        let updatedXcodeproj = try XcodeProj(path: projectPath)
        let updatedProject = try updatedXcodeproj.pbxproj.rootProject()
        #expect(updatedProject?.remotePackages.count == 1)
        #expect(
            updatedProject?.remotePackages.first?.repositoryURL
                == "https://github.com/apple/swift-collections.git")
    }
}
