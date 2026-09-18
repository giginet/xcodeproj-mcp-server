import Foundation
import MCP
import PathKit
import Testing
import XcodeProjectFormat

@testable import XcodeProjectMCP

@Suite("ProjectFormat Detection Tests", .temporaryDirectory)
struct ProjectFormatDetectionTests {
    @Test("Detects pbxproj-only bundle")
    func detectsPBXProj() throws {
        let projectPath = Path(TemporaryDirectory.url.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let format = try ProjectFormat.detect(
            atProjectBundle: URL(fileURLWithPath: projectPath.string))
        #expect(format == .pbxproj)
    }

    @Test("Detects xcproj-only bundle")
    func detectsXCProj() throws {
        let projectPath = Path(TemporaryDirectory.url.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProject(name: "TestProject", at: projectPath)

        let format = try ProjectFormat.detect(
            atProjectBundle: URL(fileURLWithPath: projectPath.string))
        #expect(format == .xcproj)
    }

    @Test("Prefers xcproj when both files exist")
    func prefersXCProjWhenBothExist() throws {
        let projectPath = Path(TemporaryDirectory.url.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        try TestXCProjHelper.write(TestXCProjHelper.makeBaseProject(), to: projectPath)

        let format = try ProjectFormat.detect(
            atProjectBundle: URL(fileURLWithPath: projectPath.string))
        #expect(format == .xcproj)
    }

    @Test("Throws when neither file exists")
    func throwsWhenEmpty() throws {
        let projectPath = Path(TemporaryDirectory.url.path) + "Empty.xcodeproj"
        try FileManager.default.createDirectory(
            atPath: projectPath.string, withIntermediateDirectories: true)

        #expect(throws: MCPError.self) {
            try ProjectFormat.detect(atProjectBundle: URL(fileURLWithPath: projectPath.string))
        }
    }
}

@Suite("XCProjFile Tests", .temporaryDirectory)
struct XCProjFileTests {
    @Test("Round-trips load and save")
    func roundTrip() throws {
        let projectPath = Path(TemporaryDirectory.url.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath)

        let bundleURL = URL(fileURLWithPath: projectPath.string)
        let loaded = try XCProjFile.load(bundleURL: bundleURL)
        try loaded.save()
        let reloaded = try XCProjFile.load(bundleURL: bundleURL)

        #expect(loaded.project == reloaded.project)
        #expect(reloaded.project.targets.first?.name == "TestApp")
    }
}

@Suite("Unsupported Format Guard Tests", .temporaryDirectory)
struct UnsupportedFormatGuardTests {
    // All built-in tools handle both formats now; requirePBXProj remains the
    // documented guard for future tools that only support pbxproj.
    @Test("requirePBXProj rejects xcproj projects without opening them")
    func requirePBXProjRejectsXCProj() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProject(name: "TestProject", at: projectPath)

        let loader = ProjectLoader(pathUtility: PathUtility(basePath: tempDir.path))
        do {
            _ = try loader.requirePBXProj(
                projectPath: projectPath.string, toolName: "future_tool")
            Issue.record("Expected an error for an xcproj project")
        } catch let error as MCPError {
            let message = error.localizedDescription
            #expect(message.contains("does not yet support"))
            #expect(message.contains("future_tool"))
        }
    }

    @Test("requirePBXProj accepts pbxproj projects")
    func requirePBXProjAcceptsPBXProj() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let loader = ProjectLoader(pathUtility: PathUtility(basePath: tempDir.path))
        let url = try loader.requirePBXProj(
            projectPath: projectPath.string, toolName: "future_tool")
        #expect(url.lastPathComponent == "TestProject.xcodeproj")
    }
}
