import Foundation
import MCP
import PathKit
import XcodeProj

/// A project opened from a `.xcodeproj` bundle in whichever format it uses on disk.
public enum LoadedProject {
    case pbxproj(XcodeProj)
    case xcproj(XCProjFile)

    public var format: ProjectFormat {
        switch self {
        case .pbxproj: return .pbxproj
        case .xcproj: return .xcproj
        }
    }
}

/// Resolves a `project_path` argument, detects the project format, and loads it.
public struct ProjectLoader: Sendable {
    /// Tools that currently accept xcproj-format projects. Used in the error
    /// message shown when an unsupported tool is invoked on an xcproj project.
    static let xcprojSupportedToolNames = [
        "create_xcodeproj",
        "list_targets",
        "list_build_configurations",
        "list_files",
        "get_build_settings",
        "list_groups",
        "list_swift_packages",
    ]

    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    /// Resolves the path, detects the format, and loads the project.
    public func load(projectPath: String) throws -> (project: LoadedProject, url: URL) {
        let resolvedPath = try pathUtility.resolvePath(from: projectPath)
        let projectURL = URL(fileURLWithPath: resolvedPath)
        switch try ProjectFormat.detect(atProjectBundle: projectURL) {
        case .pbxproj:
            return (.pbxproj(try XcodeProj(path: Path(projectURL.path))), projectURL)
        case .xcproj:
            return (.xcproj(try XCProjFile.load(bundleURL: projectURL)), projectURL)
        }
    }

    /// Guard for tools that do not support the xcproj format yet: throws a clear
    /// error for xcproj projects without ever opening the project file, so an
    /// unsupported project can never be modified.
    @discardableResult
    public func requirePBXProj(projectPath: String, toolName: String) throws -> URL {
        let resolvedPath: String
        do {
            resolvedPath = try pathUtility.resolvePath(from: projectPath)
        } catch {
            // This guard runs before the tool's own do/catch, so surface path
            // errors as MCPError like the tools themselves would.
            throw MCPError.invalidParams(error.localizedDescription)
        }
        let projectURL = URL(fileURLWithPath: resolvedPath)
        // A missing bundle is diagnosed later by the tool's own load; this guard
        // only rejects projects positively identified as xcproj.
        if (try? ProjectFormat.detect(atProjectBundle: projectURL)) == .xcproj {
            throw MCPError.xcprojUnsupported(toolName: toolName)
        }
        return projectURL
    }
}

extension MCPError {
    static func xcprojUnsupported(toolName: String) -> MCPError {
        .invalidParams(
            "Tool '\(toolName)' does not yet support the JSON project format (project.xcproj) "
                + "introduced in Xcode 27.2, which this project uses. The project file was not "
                + "modified. Tools that currently support xcproj: "
                + ProjectLoader.xcprojSupportedToolNames.joined(separator: ", "))
    }
}
