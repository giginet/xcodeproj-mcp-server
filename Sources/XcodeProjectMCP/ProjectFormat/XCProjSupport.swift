import Foundation
import XcodeProjectFormat

/// Read helpers over the `XCSchema` model, shared by the tools' xcproj arms.
///
/// The counterpart of the PBX-specific traversal code living in each tool: all
/// direct `XCSchema` access should stay in this namespace (and `XCProjFile`) so
/// churn in the pre-1.0 xcode-project-format API stays localized.
enum XCProjSupport {
    // MARK: - Object IDs

    /// Mints a fresh 24-hex-character object ID, matching the shape Xcode uses.
    static func makeObjectID() -> XCSchema.ObjectID {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return XCSchema.ObjectID(String(hex.prefix(24)))
    }

    // MARK: - Project creation

    /// Builds a new application project equivalent to the pbxproj template
    /// created by create_xcodeproj.
    static func makeNewProject(
        name: String, organizationName: String, bundleIdentifier: String
    ) throws -> XCSchema.Project {
        let productFileName = "\(name).app"
        let productReference = XCSchema.FileReference(
            objectID: nil,
            path: try XCSchema.FilePath(base: .buildProducts, path: productFileName),
            explicitFileType: XCSchema.FileTypeID(rawValue: "wrapper.application"),
            expectedSignature: nil,
            textEncoding: nil,
            lineEnding: nil,
            includeInIndex: nil,
            buildFiles: []
        )
        let productsGroup = XCSchema.Group(
            objectID: nil,
            name: "Products",
            path: "",
            includeInIndex: nil,
            children: [.fileReference(productReference)]
        )

        let target = XCSchema.Target.native(
            XCSchema.CommonTargetProperties(
                name: name,
                objectID: makeObjectID(),
                configurationListDebugID: nil,
                dependencies: [],
                buildPhases: [
                    .sources(XCSchema.BuildPhaseProperties(objectID: makeObjectID(), name: nil)),
                    .frameworks(
                        XCSchema.BuildPhaseProperties(objectID: makeObjectID(), name: nil)),
                    .resources(XCSchema.BuildPhaseProperties(objectID: makeObjectID(), name: nil)),
                ],
                buildRules: [],
                specializedConfigurations: [],
                buildSettings: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string("\(bundleIdentifier).\(name)"),
                    "PRODUCT_NAME": .string("$(TARGET_NAME)"),
                    "SWIFT_VERSION": .string("5.0"),
                ],
                product: .namePath(
                    XCSchema.NamePath(components: [.child("Products"), .child(productFileName)])),
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

        return XCSchema.Project(
            objectID: makeObjectID(),
            rootGroupDebugID: nil,
            configurationListDebugID: nil,
            topLevelReferences: [.group(productsGroup)],
            packages: [],
            configurations: [
                XCSchema.Configuration(
                    name: XCSchema.ConfigurationName(name: "Debug"), file: nil, objectID: nil),
                XCSchema.Configuration(
                    name: XCSchema.ConfigurationName(name: "Release"), file: nil, objectID: nil),
            ],
            buildSettings: [
                "ORGANIZATION_NAME": .string(organizationName)
            ],
            defaultConfigurationName: XCSchema.ConfigurationName(name: "Release"),
            targets: [target],
            localizationInfo: XCSchema.ProjectLocalizationInfo(
                development: XCSchema.Language(rawValue: "en"), supported: []),
            requiredCapabilities: [],
            buildIndependentTargetsInParallel: true,
            lastUpgradeCheck: nil,
            lastSwiftUpdateCheck: nil,
            lastSwiftMigration: nil,
            organizationName: organizationName.isEmpty ? nil : organizationName,
            classPrefix: nil,
            productsGroup: .namePath(XCSchema.NamePath(components: [.child("Products")])),
            importedProducts: []
        )
    }

    // MARK: - Targets

    static func targetSummaries(of project: XCSchema.Project) -> [(
        name: String, productType: String
    )] {
        project.targets.map { target in
            switch target {
            case .native(let properties):
                return (properties.name, properties.productTypeID?.rawValue ?? "unknown")
            case .aggregate(let properties):
                return (properties.name, "aggregate")
            case .externalBuildSystem(let properties):
                return (properties.commonProperties.name, "external-build-system")
            }
        }
    }

    // MARK: - Build configurations

    /// Project-level configuration names plus any specialized configuration
    /// names appearing on targets, deduplicated in encounter order.
    static func configurationNames(of project: XCSchema.Project) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        let allNames =
            project.configurations.map(\.name.rawValue)
            + project.targets.flatMap { $0.commonProperties.specializedConfigurations }
            .map(\.name.rawValue)
        for name in allNames where seen.insert(name).inserted {
            names.append(name)
        }
        return names
    }

    // MARK: - Files

    /// The kinds of build phases list_files reports, matching the pbxproj arm
    /// (sources, resources, and frameworks phases).
    private static let listedPhaseKinds: Set<XCSchema.BuildPhase.Kind> = [
        .sources, .resources, .frameworks,
    ]

    /// Paths of the files belonging to the given target's sources, resources,
    /// or frameworks build phases. Returns nil when the target doesn't exist.
    ///
    /// In xcproj, membership is stored inversely to pbxproj: each
    /// `FileReference` carries `buildFiles` entries pointing at a build phase,
    /// either by the phase's objectID or by (target, phase kind, name).
    static func files(inTarget targetName: String, of project: XCSchema.Project) -> [String]? {
        guard let target = project.targets.first(where: { $0.name == targetName }) else {
            return nil
        }
        let listedPhaseIDs = Set(
            target.commonProperties.buildPhases
                .filter { listedPhaseKinds.contains($0.kind) }
                .compactMap { objectID(of: $0) }
        )

        var files: [String] = []
        forEachFileReference(in: project.topLevelReferences) { fileReference in
            let belongsToTarget = fileReference.buildFiles.contains { buildFile in
                switch buildFile.buildPhase {
                case .objectID(let id):
                    return listedPhaseIDs.contains(id)
                case .named(let target, let kind, _):
                    return target.targetName == targetName && listedPhaseKinds.contains(kind)
                }
            }
            if belongsToTarget {
                files.append(fileReference.path.stringRepresentation)
            }
        }
        return files
    }

    static func objectID(of phase: XCSchema.BuildPhase) -> XCSchema.ObjectID? {
        switch phase {
        case .frameworks(let properties), .headers(let properties),
            .javaArchive(let properties), .resources(let properties),
            .rez(let properties), .sources(let properties):
            return properties.objectID
        case .appleScript(let properties):
            return properties.baseProperties.objectID
        case .copy(let properties):
            return properties.baseProperties.objectID
        case .script(let properties):
            return properties.baseProperties.objectID
        }
    }

    private static func forEachFileReference(
        in references: [XCSchema.Reference], _ body: (XCSchema.FileReference) -> Void
    ) {
        XCProjTreeEditor.forEachFileReference(in: references, body)
    }

    // MARK: - Target mutation

    /// Mutates the common properties of the named target, rebuilding the
    /// target's enum case. Returns false when the target doesn't exist.
    @discardableResult
    static func modifyTarget(
        named targetName: String, in project: inout XCSchema.Project,
        _ body: (inout XCSchema.CommonTargetProperties) -> Void
    ) -> Bool {
        guard let index = project.targets.firstIndex(where: { $0.name == targetName }) else {
            return false
        }
        project.targets[index] = modifying(project.targets[index], body)
        return true
    }

    static func modifying(
        _ target: XCSchema.Target, _ body: (inout XCSchema.CommonTargetProperties) -> Void
    ) -> XCSchema.Target {
        switch target {
        case .native(var properties):
            body(&properties)
            return .native(properties)
        case .aggregate(var properties):
            body(&properties)
            return .aggregate(properties)
        case .externalBuildSystem(var properties):
            body(&properties.commonProperties)
            return .externalBuildSystem(properties)
        }
    }

    /// Builds an empty build phase of one of the simple kinds.
    static func makeBuildPhase(kind: XCSchema.BuildPhase.Kind, objectID: XCSchema.ObjectID? = nil)
        -> XCSchema.BuildPhase?
    {
        let properties = XCSchema.BuildPhaseProperties(objectID: objectID, name: nil)
        switch kind {
        case .sources: return .sources(properties)
        case .resources: return .resources(properties)
        case .frameworks: return .frameworks(properties)
        case .headers: return .headers(properties)
        case .javaArchive: return .javaArchive(properties)
        case .rez: return .rez(properties)
        case .appleScript, .copy, .script: return nil
        }
    }

    /// Ensures the target has a build phase of the given simple kind, so a
    /// `.named` build-file reference to it resolves.
    static func ensureBuildPhase(
        kind: XCSchema.BuildPhase.Kind, in properties: inout XCSchema.CommonTargetProperties
    ) {
        guard !properties.buildPhases.contains(where: { $0.kind == kind }),
            let phase = makeBuildPhase(kind: kind)
        else { return }
        properties.buildPhases.append(phase)
    }

    /// Build-file properties carrying no customization.
    static func emptyBuildFileProperties() -> XCSchema.BuildFileProperties {
        XCSchema.BuildFileProperties(
            platformFilters: [],
            additionalBuildFlags: nil,
            assetTags: [],
            attributes: emptyBuildFileAttributes()
        )
    }

    static func emptyBuildFileAttributes() -> XCSchema.BuildFileAttributes {
        XCSchema.BuildFileAttributes(
            headerRole: nil,
            machInterfaceGeneration: nil,
            isWeak: false,
            codeSignOnCopy: false,
            codeGeneration: .default,
            headerPreservation: .keep,
            decompress: false,
            codeGenerationVisibility: nil
        )
    }

    /// A membership entry mapping a file into the named target's phase of the
    /// given kind (and optional phase name, for copy/script phases).
    static func makeBuildFile(
        targetName: String, kind: XCSchema.BuildPhase.Kind, phaseName: String? = nil,
        properties: XCSchema.BuildFileProperties? = nil
    ) -> XCSchema.ProjectBuildFile {
        XCSchema.ProjectBuildFile(
            objectID: nil,
            buildPhase: .named(
                target: XCSchema.LocalTargetReference(targetName: targetName),
                kind: kind, name: phaseName),
            properties: properties ?? emptyBuildFileProperties()
        )
    }

    /// Whether a build-file entry maps into the given target, addressed either
    /// by name or through one of the target's phase object IDs.
    static func buildFile(
        _ buildFile: XCSchema.ProjectBuildFile, belongsTo targetName: String,
        phaseIDs: Set<XCSchema.ObjectID>, kinds: Set<XCSchema.BuildPhase.Kind>? = nil
    ) -> Bool {
        switch buildFile.buildPhase {
        case .objectID(let id):
            return phaseIDs.contains(id)
        case .named(let target, let kind, _):
            guard target.targetName == targetName else { return false }
            guard let kinds else { return true }
            return kinds.contains(kind)
        }
    }

    static func phaseObjectIDs(
        of target: XCSchema.Target, kinds: Set<XCSchema.BuildPhase.Kind>? = nil
    ) -> Set<XCSchema.ObjectID> {
        Set(
            target.commonProperties.buildPhases
                .filter { kinds == nil || kinds!.contains($0.kind) }
                .compactMap { objectID(of: $0) }
        )
    }

    /// Copies build phases, minting a fresh object ID for every phase that has
    /// one, and returns the old-to-new ID mapping (used to duplicate matching
    /// `buildFiles` entries when duplicating a target).
    static func withReassignedPhaseObjectIDs(_ phases: [XCSchema.BuildPhase])
        -> (phases: [XCSchema.BuildPhase], mapping: [XCSchema.ObjectID: XCSchema.ObjectID])
    {
        var mapping: [XCSchema.ObjectID: XCSchema.ObjectID] = [:]
        func remap(_ properties: inout XCSchema.BuildPhaseProperties) {
            guard let old = properties.objectID else { return }
            let new = makeObjectID()
            mapping[old] = new
            properties.objectID = new
        }
        let newPhases = phases.map { phase -> XCSchema.BuildPhase in
            switch phase {
            case .sources(var properties):
                remap(&properties)
                return .sources(properties)
            case .resources(var properties):
                remap(&properties)
                return .resources(properties)
            case .frameworks(var properties):
                remap(&properties)
                return .frameworks(properties)
            case .headers(var properties):
                remap(&properties)
                return .headers(properties)
            case .javaArchive(var properties):
                remap(&properties)
                return .javaArchive(properties)
            case .rez(var properties):
                remap(&properties)
                return .rez(properties)
            case .appleScript(var properties):
                remap(&properties.baseProperties)
                return .appleScript(properties)
            case .copy(var properties):
                remap(&properties.baseProperties)
                return .copy(properties)
            case .script(var properties):
                remap(&properties.baseProperties)
                return .script(properties)
            }
        }
        return (newPhases, mapping)
    }

    /// Names of the targets a file reference is mapped into.
    static func targetNames(
        referencedBy fileReference: XCSchema.FileReference, in project: XCSchema.Project
    ) -> [String] {
        var names: [String] = []
        for target in project.targets {
            let ids = phaseObjectIDs(of: target)
            let belongs = fileReference.buildFiles.contains {
                buildFile($0, belongsTo: target.name, phaseIDs: ids)
            }
            if belongs, !names.contains(target.name) {
                names.append(target.name)
            }
        }
        return names
    }

    // MARK: - Build settings

    /// The target's flat build settings, formatted as "KEY = value" lines.
    ///
    /// xcproj has no per-configuration setting dictionaries; see
    /// `configurationNote(for:target:in:)`.
    static func buildSettingLines(of target: XCSchema.Target) -> [String] {
        target.commonProperties.buildSettings
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                switch value {
                case .string(let string):
                    return "  \(key) = \(string)"
                case .array(let array):
                    return "  \(key) = \(array.joined(separator: " "))"
                }
            }
    }

    /// A note explaining how the requested configuration relates to the flat
    /// settings, or nil when the configuration doesn't exist anywhere.
    static func configurationNote(
        for configurationName: String, target: XCSchema.Target, in project: XCSchema.Project
    ) -> String? {
        let specialized = target.commonProperties.specializedConfigurations
            .first(where: { $0.name.rawValue == configurationName })
        let existsOnProject = project.configurations.contains {
            $0.name.rawValue == configurationName
        }
        guard specialized != nil || existsOnProject else { return nil }

        var note =
            "Note: xcproj stores one flat build settings dictionary per target; "
            + "configuration '\(configurationName)' has no inline overrides."
        if let file = specialized?.file {
            note += " Configuration-specific settings come from the xcconfig file '\(file)'."
        }
        return note
    }

    // MARK: - Groups

    /// Hierarchical "Parent/Child" listing of groups, folder references, and
    /// synchronized folders, matching the pbxproj arm's output format.
    static func groupPaths(of project: XCSchema.Project) -> [String] {
        var groupList: [String] = []
        traverse(project.topLevelReferences, path: "", groupList: &groupList)
        return groupList
    }

    private static func traverse(
        _ references: [XCSchema.Reference], path: String, groupList: inout [String]
    ) {
        func joined(_ name: String) -> String {
            path.isEmpty ? name : "\(path)/\(name)"
        }
        for reference in references {
            switch reference {
            case .group(let group):
                let name = group.name.isEmpty ? group.path.stringRepresentation : group.name
                let currentPath = joined(name)
                groupList.append("- \(currentPath)")
                traverse(group.children, path: currentPath, groupList: &groupList)
            case .folder(let folder):
                groupList.append(
                    "- \(joined(folder.path.stringRepresentation)) (file system synchronized)")
            case .fileReference(let fileReference):
                if fileReference.explicitFileType?.rawValue == "folder" {
                    groupList.append(
                        "- \(joined(fileReference.path.stringRepresentation)) (folder reference)")
                }
            case .variantGroup, .versionGroup:
                continue
            }
        }
    }

    // MARK: - Swift packages

    /// Package descriptions using the same "📦 url (requirement)" / "📁 path
    /// (local)" format as the pbxproj arm.
    static func packageDescriptions(of project: XCSchema.Project) -> [String] {
        project.packages.map { package in
            switch package.location {
            case .remote(let remote):
                let requirement = remote.versionConstraint.map(format(constraint:)) ?? "unknown"
                return "📦 \(remote.repositoryURL) (\(requirement))"
            case .local(let local):
                return "📁 \(local.path) (local)"
            }
        }
    }

    private static func format(constraint: XCSchema.SwiftPackageVersionConstraint) -> String {
        switch constraint {
        case .version(let version):
            return "exact: \(version)"
        case .upToNextMajorVersion(let version):
            return "from: \(version)"
        case .upToNextMinorVersion(let version):
            return "upToNextMinor: \(version)"
        case .versionRange(let min, let max):
            return "range: \(min) - \(max)"
        case .branch(let branch):
            return "branch: \(branch)"
        case .revision(let revision):
            return "revision: \(revision)"
        }
    }
}
