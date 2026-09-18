import Foundation
import MCP

/// The on-disk representation of an Xcode project inside a `.xcodeproj` bundle.
public enum ProjectFormat: String, Sendable, CaseIterable {
    /// The legacy OpenStep-plist `project.pbxproj` format.
    case pbxproj
    /// The JSON-based `project.xcproj` format introduced in Xcode 27.2.
    case xcproj

    /// The file name this format uses inside the `.xcodeproj` bundle.
    public var fileName: String {
        switch self {
        case .pbxproj: return "project.pbxproj"
        case .xcproj: return "project.xcproj"
        }
    }

    /// Detects the format of the project bundle at the given URL.
    ///
    /// When both files are present, `project.xcproj` wins, matching Xcode 27.2's
    /// own priority.
    public static func detect(atProjectBundle bundleURL: URL) throws -> ProjectFormat {
        let fileManager = FileManager.default
        if fileManager.fileExists(
            atPath: bundleURL.appendingPathComponent(ProjectFormat.xcproj.fileName).path)
        {
            return .xcproj
        }
        if fileManager.fileExists(
            atPath: bundleURL.appendingPathComponent(ProjectFormat.pbxproj.fileName).path)
        {
            return .pbxproj
        }
        throw MCPError.invalidParams(
            "No project.pbxproj or project.xcproj found inside '\(bundleURL.lastPathComponent)'")
    }
}
