import Foundation

public enum PathError: LocalizedError {
    case pathOutsideBasePath(path: String, basePath: String)

    public var errorDescription: String? {
        switch self {
        case .pathOutsideBasePath(let path, let basePath):
            return "Path '\(path)' is outside the allowed base path '\(basePath)'"
        }
    }
}

public struct PathUtility: Sendable {
    private let basePath: String

    public init(basePath: String) {
        self.basePath = basePath
    }

    /// Resolves a path relative to the base path and validates it's within bounds
    public func resolvePath(from path: String) throws -> String {
        let resolvedURL = try resolvePathURL(from: path)
        return resolvedURL.path
    }

    /// Resolves a path URL relative to the base path and validates it's within bounds
    public func resolvePathURL(from path: String) throws -> URL {
        let baseURL = URL(fileURLWithPath: basePath).standardized

        let resolvedURL: URL
        if path.hasPrefix("/") {
            // Absolute path - must validate it's within base path
            resolvedURL = URL(fileURLWithPath: path).standardized
        } else {
            // Relative path - resolve relative to base path
            resolvedURL = baseURL.appendingPathComponent(path).standardized
        }

        // Validate the resolved path is within the base path
        let basePath = baseURL.path
        let resolvedPath = resolvedURL.path

        if !resolvedPath.hasPrefix(basePath) {
            throw PathError.pathOutsideBasePath(path: resolvedPath, basePath: basePath)
        }

        return resolvedURL
    }

    /// Converts an absolute path to a relative path from the base path
    public func makeRelativePath(from absolutePath: String) -> String? {
        let baseURL = URL(fileURLWithPath: basePath).standardized
        let absoluteURL = URL(fileURLWithPath: absolutePath).standardized

        // Check if the absolute path is within the base path
        guard absoluteURL.path.hasPrefix(baseURL.path) else {
            return nil
        }

        return PathUtility.relativePath(from: basePath, to: absolutePath)
    }

    /// Converts an absolute path to a relative path from an arbitrary directory.
    ///
    /// Unlike `makeRelativePath(from:)`, which is always relative to the server's
    /// sandbox `basePath`, this lets callers compute a path relative to some other
    /// directory -- e.g. the directory that actually governs how a `PBXFileReference`
    /// with `sourceTree: .group` resolves on disk, which is not necessarily `basePath`.
    public static func relativePath(from directory: String, to absolutePath: String) -> String? {
        let baseURL = URL(fileURLWithPath: directory).standardized
        let absoluteURL = URL(fileURLWithPath: absolutePath).standardized

        // Get the relative components
        let baseComponents = baseURL.pathComponents
        let absoluteComponents = absoluteURL.pathComponents

        // Find common prefix
        var commonPrefixLength = 0
        for i in 0..<min(baseComponents.count, absoluteComponents.count) {
            if baseComponents[i] == absoluteComponents[i] {
                commonPrefixLength += 1
            } else {
                break
            }
        }

        // Build relative path
        let upComponents = Array(repeating: "..", count: baseComponents.count - commonPrefixLength)
        let downComponents = Array(absoluteComponents[commonPrefixLength...])
        let relativeComponents = upComponents + downComponents

        if relativeComponents.isEmpty {
            return "."
        }

        return relativeComponents.joined(separator: "/")
    }

    // Legacy static methods for backward compatibility
    static func resolvePathURL(from path: String) -> URL {
        let url = URL(fileURLWithPath: path)

        if url.path.hasPrefix("/") {
            return url
        } else {
            let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            return currentDirectory.appendingPathComponent(path).standardized
        }
    }

    static func resolvePath(from path: String) -> String {
        return resolvePathURL(from: path).path
    }
}
