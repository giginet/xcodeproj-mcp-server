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

@Suite("Unsupported Format Tool Tests", .temporaryDirectory)
struct UnsupportedFormatToolTests {
    @Test("Write tools reject xcproj projects without modifying them")
    func writeToolsRejectXCProj() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestXCProjHelper.createTestXCProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        let xcprojURL = URL(fileURLWithPath: projectPath.string)
            .appendingPathComponent("project.xcproj")
        let originalContents = try Data(contentsOf: xcprojURL)

        let pathUtility = PathUtility(basePath: tempDir.path)
        let project = Value.string(projectPath.string)
        let cases: [(toolName: String, execute: () throws -> CallTool.Result)] = [
            (
                "add_file",
                {
                    try AddFileTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "file_path": .string("main.swift"),
                    ])
                }
            ),
            (
                "remove_file",
                {
                    try RemoveFileTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "file_path": .string("main.swift"),
                    ])
                }
            ),
            (
                "move_file",
                {
                    try MoveFileTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "old_path": .string("a.swift"),
                        "new_path": .string("b.swift"),
                    ])
                }
            ),
            (
                "create_group",
                {
                    try CreateGroupTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "group_name": .string("NewGroup"),
                    ])
                }
            ),
            (
                "add_target",
                {
                    try AddTargetTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("NewTarget"),
                        "product_type": .string("framework"),
                        "bundle_identifier": .string("com.example.new"),
                    ])
                }
            ),
            (
                "remove_target",
                {
                    try RemoveTargetTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("App"),
                    ])
                }
            ),
            (
                "add_dependency",
                {
                    try AddDependencyTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("App"),
                        "dependency_name": .string("Other"),
                    ])
                }
            ),
            (
                "set_build_setting",
                {
                    try SetBuildSettingTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("App"),
                        "configuration": .string("Debug"),
                        "setting_name": .string("SWIFT_VERSION"),
                        "setting_value": .string("6.0"),
                    ])
                }
            ),
            (
                "add_framework",
                {
                    try AddFrameworkTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("App"),
                        "framework_name": .string("UIKit.framework"),
                    ])
                }
            ),
            (
                "add_build_phase",
                {
                    try AddBuildPhaseTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "target_name": .string("App"),
                        "phase_name": .string("Script"), "phase_type": .string("run_script"),
                    ])
                }
            ),
            (
                "duplicate_target",
                {
                    try DuplicateTargetTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "source_target": .string("App"),
                        "new_target_name": .string("App2"),
                    ])
                }
            ),
            (
                "add_swift_package",
                {
                    try AddSwiftPackageTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project,
                        "package_url": .string("https://github.com/example/package"),
                        "requirement": .string("1.0.0"),
                    ])
                }
            ),
            (
                "remove_swift_package",
                {
                    try RemoveSwiftPackageTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project,
                        "package_url": .string("https://github.com/example/package"),
                    ])
                }
            ),
            (
                "add_synchronized_folder",
                {
                    try AddFolderTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "folder_path": .string("Sources"),
                    ])
                }
            ),
            (
                "add_app_extension",
                {
                    try AddAppExtensionTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "extension_name": .string("Widget"),
                        "extension_type": .string("widget"),
                        "host_target_name": .string("App"),
                        "bundle_identifier": .string("com.example.app.widget"),
                    ])
                }
            ),
            (
                "remove_app_extension",
                {
                    try RemoveAppExtensionTool(pathUtility: pathUtility).execute(arguments: [
                        "project_path": project, "extension_name": .string("Widget"),
                    ])
                }
            ),
        ]

        for testCase in cases {
            do {
                _ = try testCase.execute()
                Issue.record("Tool '\(testCase.toolName)' should reject an xcproj project")
            } catch let error as MCPError {
                let message = error.localizedDescription
                #expect(
                    message.contains("does not yet support"),
                    "Unexpected error for '\(testCase.toolName)': \(message)")
                #expect(message.contains(testCase.toolName))
            }
        }

        // The guard must reject before ever opening the project file.
        let contentsAfter = try Data(contentsOf: xcprojURL)
        #expect(contentsAfter == originalContents)
    }
}
