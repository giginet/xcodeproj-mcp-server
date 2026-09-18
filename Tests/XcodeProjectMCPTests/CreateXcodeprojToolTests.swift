import Foundation
import MCP
import PathKit
import Testing
import XcodeProj

@testable import XcodeProjectMCP

@Test("CreateXcodeprojTool has correct properties")
func toolProperties() {
    let createTool = CreateXcodeprojTool(pathUtility: PathUtility(basePath: "/tmp"))
    let tool = createTool.tool()

    #expect(tool.name == "create_xcodeproj")
    #expect(tool.description == "Create a new Xcode project file (.xcodeproj)")
    #expect(tool.inputSchema != nil)
}

@Test("CreateXcodeprojTool can be executed")
func toolExecution() throws {
    let createTool = CreateXcodeprojTool(pathUtility: PathUtility(basePath: "/tmp"))

    // This test just verifies the tool can be instantiated and has the right interface
    // We don't test actual file creation here to avoid side effects
    #expect(createTool.tool().name == "create_xcodeproj")
}

@Test("CreateXcodeprojTool creates project with bundle identifier")
func createProjectWithBundleIdentifier() throws {
    let tempDir = Path("/tmp/xcodeproj-test-\(UUID().uuidString)")
    try tempDir.mkpath()
    let createTool = CreateXcodeprojTool(pathUtility: PathUtility(basePath: tempDir.string))

    defer {
        try? tempDir.delete()
    }

    let arguments: [String: Value] = [
        "project_name": Value.string("TestApp"),
        "path": Value.string(tempDir.string),
        "organization_name": Value.string("Test Org"),
        "bundle_identifier": Value.string("com.testorg"),
    ]

    let result = try createTool.execute(arguments: arguments)

    // Verify project was created
    let projectPath = tempDir + "TestApp.xcodeproj"
    #expect(projectPath.exists)

    // Read and verify the project contains the bundle identifier
    let xcodeproj = try XcodeProj(path: projectPath)
    let pbxproj = xcodeproj.pbxproj

    // Find the app target
    let appTarget = pbxproj.nativeTargets.first { $0.name == "TestApp" }
    #expect(appTarget != nil)

    // Check that bundle identifier is set in build configurations
    if let target = appTarget,
        let configList = target.buildConfigurationList,
        let config = configList.buildConfigurations.first
    {
        let bundleId = config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]
        #expect(bundleId == .string("com.testorg.TestApp"))
    } else {
        Issue.record("Could not find target build configuration")
    }

    #expect(result.isError != true)
}

@Test("Create xcproj-format project")
func createXCProjFormatProject() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tool = CreateXcodeprojTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
        "project_name": .string("XCProjApp"),
        "path": .string("."),
        "organization_name": .string("Example Org"),
        "bundle_identifier": .string("com.example"),
        "format": .string("xcproj"),
    ])

    guard case let .text(message, _, _) = result.content.first else {
        Issue.record("Expected text result")
        return
    }
    #expect(message.contains("Successfully created"))

    let bundleURL = tempDir.appendingPathComponent("XCProjApp.xcodeproj")
    #expect(
        FileManager.default.fileExists(
            atPath: bundleURL.appendingPathComponent("project.xcproj").path))
    #expect(
        !FileManager.default.fileExists(
            atPath: bundleURL.appendingPathComponent("project.pbxproj").path))

    let loaded = try XCProjFile.load(bundleURL: bundleURL)
    #expect(loaded.project.targets.first?.name == "XCProjApp")
}
