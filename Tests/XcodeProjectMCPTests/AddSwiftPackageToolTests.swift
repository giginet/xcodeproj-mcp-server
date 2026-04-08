import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Suite("AddSwiftPackageTool Tests")
struct AddSwiftPackageToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_swift_package")
        #expect(toolDefinition.description == "Add a Swift Package dependency to an Xcode project")
    }

    @Test("Add package with missing parameters")
    func addPackageWithMissingParameters() throws {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
                "requirement": Value.string("5.0.0"),
            ])
        }

        // Missing package_url
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "requirement": Value.string("5.0.0"),
            ])
        }

        // Missing requirement
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
            ])
        }
    }

    @Test("Add Swift Package with exact version")
    func addSwiftPackageWithExactVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
            "requirement": Value.string("5.0.0"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))
        #expect(message.contains("alamofire"))
        #expect(message.contains("5.0.0"))

        // Verify package was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == "https://github.com/alamofire/alamofire.git"
        }
        #expect(packageRef != nil)
        #expect(packageRef?.versionRequirement == .exact("5.0.0"))
    }

    @Test("Add Swift Package with from version")
    func addSwiftPackageWithFromVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string(
                "https://github.com/pointfreeco/swift-composable-architecture.git"),
            "requirement": Value.string("from: 1.0.0"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))

        // Verify package was added with correct requirement
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == "https://github.com/pointfreeco/swift-composable-architecture.git"
        }
        #expect(packageRef != nil)
        #expect(packageRef?.versionRequirement == .upToNextMajorVersion("1.0.0"))
    }

    @Test("Add Swift Package with branch")
    func addSwiftPackageWithBranch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-algorithms.git"),
            "requirement": Value.string("branch: main"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))

        // Verify package was added with branch requirement
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == "https://github.com/apple/swift-algorithms.git"
        }
        #expect(packageRef != nil)
        #expect(packageRef?.versionRequirement == .branch("main"))
    }

    @Test("Add Swift Package to specific target")
    func addSwiftPackageToSpecificTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/realm/realm-swift.git"),
            "requirement": Value.string("10.0.0"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("RealmSwift"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))
        #expect(message.contains("to target 'TestApp'"))

        // Verify package was added and linked to target
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == "https://github.com/realm/realm-swift.git"
        }
        #expect(packageRef != nil)

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil)
        #expect(target?.packageProductDependencies?.count == 1)
    }

    @Test("Add duplicate Swift Package")
    func addDuplicateSwiftPackage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
        ]

        // Add package first time
        _ = try tool.execute(arguments: args)

        // Try to add same package again
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Add package with invalid target")
    func addPackageWithInvalidTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("NonExistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
