import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("ListSwiftPackagesTool Tests")
struct ListSwiftPackagesToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_swift_packages")
        #expect(
            toolDefinition.description == "List all Swift Package dependencies in an Xcode project")
    }

    @Test("List packages with missing project path")
    func listPackagesWithMissingProjectPath() throws {
        let tool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test("List packages from empty project")
    func listPackagesFromEmptyProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string)
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No Swift Package dependencies found"))
    }

    @Test("List packages with remote packages")
    func listPackagesWithRemotePackages() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add some packages to the project first
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Add Alamofire with exact version
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/Alamofire/Alamofire.git"),
            "requirement": Value.string("5.0.0"),
        ])

        // Add RxSwift with from version
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/ReactiveX/RxSwift.git"),
            "requirement": Value.string("from: 6.0.0"),
        ])

        // Add Swift Collections with branch
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("branch: main"),
        ])

        // Now list the packages
        let listTool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string)
        ]

        let result = try listTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }

        #expect(message.contains("Swift Package dependencies:"))
        #expect(message.contains("📦 https://github.com/Alamofire/Alamofire.git"))
        #expect(message.contains("exact: 5.0.0"))
        #expect(message.contains("📦 https://github.com/ReactiveX/RxSwift.git"))
        #expect(message.contains("from: 6.0.0"))
        #expect(message.contains("📦 https://github.com/apple/swift-collections.git"))
        #expect(message.contains("branch: main"))
    }

    @Test("List packages with local packages")
    func listPackagesWithLocalPackages() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Manually add a local package to test
        let xcodeproj = try XcodeProj(path: projectPath)
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            Issue.record("Unable to access project root")
            return
        }

        let localPackage = XCLocalSwiftPackageReference(relativePath: "../MyLocalPackage")
        xcodeproj.pbxproj.add(object: localPackage)
        project.localPackages.append(localPackage)

        try xcodeproj.write(path: projectPath)

        // Now list the packages
        let listTool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string)
        ]

        let result = try listTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }

        #expect(message.contains("Swift Package dependencies:"))
        #expect(message.contains("📁 ../MyLocalPackage (local)"))
    }

    @Test("List packages with mixed remote and local packages")
    func listPackagesWithMixedPackages() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a remote package
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-algorithms.git"),
            "requirement": Value.string("revision: abc123"),
        ])

        // Add a local package
        let xcodeproj = try XcodeProj(path: projectPath)
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            Issue.record("Unable to access project root")
            return
        }

        let localPackage = XCLocalSwiftPackageReference(relativePath: "../SharedUtilities")
        xcodeproj.pbxproj.add(object: localPackage)
        project.localPackages.append(localPackage)

        try xcodeproj.write(path: projectPath)

        // Now list the packages
        let listTool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string)
        ]

        let result = try listTool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }

        #expect(message.contains("Swift Package dependencies:"))
        #expect(message.contains("📦 https://github.com/apple/swift-algorithms.git"))
        #expect(message.contains("revision: abc123"))
        #expect(message.contains("📁 ../SharedUtilities (local)"))
    }
}
