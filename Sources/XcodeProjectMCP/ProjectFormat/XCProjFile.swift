import Foundation
import XcodeProjectFormat

/// An `XCSchema.Project` loaded from a `.xcodeproj` bundle's `project.xcproj`.
///
/// `XCSchema` models are value types: mutate `project` (typically through helpers
/// taking `inout XCSchema.Project`) and call `save()` to persist the changes.
/// `save()` only ever writes `project.xcproj`, so a project's format is always
/// preserved and never converted implicitly.
public struct XCProjFile {
    public var project: XCSchema.Project
    public let bundleURL: URL

    public init(project: XCSchema.Project, bundleURL: URL) {
        self.project = project
        self.bundleURL = bundleURL
    }

    private var fileURL: URL {
        bundleURL.appendingPathComponent(ProjectFormat.xcproj.fileName)
    }

    public static func load(bundleURL: URL) throws -> XCProjFile {
        let fileURL = bundleURL.appendingPathComponent(ProjectFormat.xcproj.fileName)
        let data = try Data(contentsOf: fileURL)
        let project = try XCSchema.Project(jsonRepresentation: data)
        return XCProjFile(project: project, bundleURL: bundleURL)
    }

    public func save() throws {
        try project.jsonRepresentation().write(to: fileURL, options: .atomic)
    }
}
