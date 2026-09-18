import Foundation
import PathKit
import XcodeProjectFormat

@testable import XcodeProjectMCP

/// XCSchema counterpart of TestProjectHelper: builds xcproj-format fixtures
/// (a `.xcodeproj` bundle containing only `project.xcproj`) with the same
/// shapes and setting values as the pbxproj fixtures.
struct TestXCProjHelper {
    static func createTestXCProject(name: String, at path: Path) throws {
        var project = makeBaseProject()
        project.topLevelReferences.append(
            .group(makeGroup(name: "Tests", path: "Tests"))
        )
        try write(project, to: path)
    }

    static func createTestXCProjectWithTarget(name: String, targetName: String, at path: Path)
        throws
    {
        var project = makeBaseProject()
        project.targets.append(makeApplicationTarget(named: targetName))
        try write(project, to: path)
    }

    /// Nested groups fixture: TopLevel -> Nested -> DeeplyNested.
    static func createTestXCProjectWithNestedGroups(name: String, at path: Path) throws {
        var project = makeBaseProject()
        var topLevel = makeGroup(name: "TopLevel", path: "TopLevel")
        var nested = makeGroup(name: "Nested", path: "Nested")
        nested.children = [.group(makeGroup(name: "DeeplyNested", path: "DeeplyNested"))]
        topLevel.children = [.group(nested)]
        project.topLevelReferences.append(.group(topLevel))
        try write(project, to: path)
    }

    /// A target plus file references whose `buildFiles` map them into the
    /// target's sources build phase.
    static func createTestXCProjectWithFiles(
        name: String, targetName: String, fileNames: [String], at path: Path
    ) throws {
        var project = makeBaseProject()
        project.targets.append(makeApplicationTarget(named: targetName))

        let files = try fileNames.map { fileName in
            XCSchema.Reference.fileReference(
                XCSchema.FileReference(
                    objectID: nil,
                    path: try XCSchema.FilePath(base: .group, path: fileName),
                    explicitFileType: nil,
                    expectedSignature: nil,
                    textEncoding: nil,
                    lineEnding: nil,
                    includeInIndex: nil,
                    buildFiles: [
                        XCSchema.ProjectBuildFile(
                            objectID: nil,
                            buildPhase: .named(
                                target: XCSchema.LocalTargetReference(targetName: targetName),
                                kind: .sources, name: nil),
                            properties: makeEmptyBuildFileProperties()
                        )
                    ]
                ))
        }
        var sourcesGroup = makeGroup(name: "Sources", path: "Sources")
        sourcesGroup.children = files
        project.topLevelReferences.append(.group(sourcesGroup))
        try write(project, to: path)
    }

    static func createTestXCProjectWithPackages(name: String, at path: Path) throws {
        var project = makeBaseProject()
        project.packages = [
            XCSchema.SwiftPackage(
                location: .remote(
                    XCSchema.RemoteSwiftPackage(
                        repositoryURL: "https://github.com/example/package",
                        versionConstraint: .upToNextMajorVersion("1.0.0")
                    )),
                traits: []
            ),
            XCSchema.SwiftPackage(
                location: .local(XCSchema.LocalSwiftPackage(path: "../LocalPackage")),
                traits: []
            ),
        ]
        try write(project, to: path)
    }

    // MARK: - Building blocks

    static func makeBaseProject() -> XCSchema.Project {
        XCSchema.Project(
            objectID: XCProjSupport.makeObjectID(),
            rootGroupDebugID: nil,
            configurationListDebugID: nil,
            topLevelReferences: [],
            packages: [],
            configurations: [
                XCSchema.Configuration(
                    name: XCSchema.ConfigurationName(name: "Debug"), file: nil, objectID: nil),
                XCSchema.Configuration(
                    name: XCSchema.ConfigurationName(name: "Release"), file: nil, objectID: nil),
            ],
            buildSettings: [:],
            defaultConfigurationName: XCSchema.ConfigurationName(name: "Release"),
            targets: [],
            localizationInfo: XCSchema.ProjectLocalizationInfo(
                development: XCSchema.Language(rawValue: "en"), supported: []),
            requiredCapabilities: [],
            buildIndependentTargetsInParallel: true,
            lastUpgradeCheck: nil,
            lastSwiftUpdateCheck: nil,
            lastSwiftMigration: nil,
            organizationName: nil,
            classPrefix: nil,
            productsGroup: nil,
            importedProducts: []
        )
    }

    static func makeApplicationTarget(named targetName: String) -> XCSchema.Target {
        .native(
            XCSchema.CommonTargetProperties(
                name: targetName,
                objectID: XCProjSupport.makeObjectID(),
                configurationListDebugID: nil,
                dependencies: [],
                buildPhases: [
                    .sources(
                        XCSchema.BuildPhaseProperties(
                            objectID: XCProjSupport.makeObjectID(), name: nil)),
                    .resources(
                        XCSchema.BuildPhaseProperties(
                            objectID: XCProjSupport.makeObjectID(), name: nil)),
                ],
                buildRules: [],
                specializedConfigurations: [],
                buildSettings: [
                    "PRODUCT_NAME": .string(targetName),
                    "BUNDLE_IDENTIFIER": .string("com.example.\(targetName)"),
                ],
                product: nil,
                productTypeID: XCSchema.ProductTypeID(
                    rawValue: "com.apple.product-type.application"),
                testHostTarget: nil,
                legacyProvisioningStyle: nil,
                legacyTeamID: nil,
                lastSwiftUpdateCheck: nil,
                lastSwiftMigration: nil,
                packageProductTargetMembers: []
            )
        )
    }

    static func makeGroup(name: String, path: String) -> XCSchema.Group {
        XCSchema.Group(
            objectID: nil,
            name: name,
            path: XCSchema.FilePath(stringLiteral: path),
            includeInIndex: nil,
            children: []
        )
    }

    static func makeEmptyBuildFileProperties() -> XCSchema.BuildFileProperties {
        XCSchema.BuildFileProperties(
            platformFilters: [],
            additionalBuildFlags: nil,
            assetTags: [],
            attributes: XCSchema.BuildFileAttributes(
                headerRole: nil,
                machInterfaceGeneration: nil,
                isWeak: false,
                codeSignOnCopy: false,
                codeGeneration: .default,
                headerPreservation: .keep,
                decompress: false,
                codeGenerationVisibility: nil
            )
        )
    }

    static func write(_ project: XCSchema.Project, to path: Path) throws {
        try FileManager.default.createDirectory(
            atPath: path.string, withIntermediateDirectories: true)
        try XCProjFile(project: project, bundleURL: URL(fileURLWithPath: path.string)).save()
    }
}

/// Format-dispatching facade so a test body can run against both formats via
/// `@Test(arguments: ProjectFormat.allCases)`.
enum TestProjectFixture {
    static func createProject(format: ProjectFormat, name: String, at path: Path) throws {
        switch format {
        case .pbxproj:
            try TestProjectHelper.createTestProject(name: name, at: path)
        case .xcproj:
            try TestXCProjHelper.createTestXCProject(name: name, at: path)
        }
    }

    static func createProjectWithTarget(
        format: ProjectFormat, name: String, targetName: String, at path: Path
    ) throws {
        switch format {
        case .pbxproj:
            try TestProjectHelper.createTestProjectWithTarget(
                name: name, targetName: targetName, at: path)
        case .xcproj:
            try TestXCProjHelper.createTestXCProjectWithTarget(
                name: name, targetName: targetName, at: path)
        }
    }

    static func createProjectWithNestedGroups(format: ProjectFormat, name: String, at path: Path)
        throws
    {
        switch format {
        case .pbxproj:
            try TestProjectHelper.createTestProjectWithNestedGroups(name: name, at: path)
        case .xcproj:
            try TestXCProjHelper.createTestXCProjectWithNestedGroups(name: name, at: path)
        }
    }
}
