import Foundation
import MCP
import PathKit
import XcodeProj

public struct AddSwiftPackageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_swift_package",
            description: "Add a Swift Package dependency to an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "package_url": .object([
                        "type": .string("string"),
                        "description": .string("URL of the Swift Package repository"),
                    ]),
                    "requirement": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Version requirement (e.g., '1.0.0', 'from: 1.0.0', 'upToNextMajor: 1.0.0', 'branch: main')"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Target to add the package to (optional)"),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string("Specific product name to link (optional)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("package_url"), .string("requirement"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(packageURL) = arguments["package_url"],
            case let .string(requirement) = arguments["requirement"]
        else {
            throw MCPError.invalidParams("project_path, package_url, and requirement are required")
        }

        let targetName: String?
        if case let .string(target) = arguments["target_name"] {
            targetName = target
        } else {
            targetName = nil
        }

        let productName: String?
        if case let .string(product) = arguments["product_name"] {
            productName = product
        } else {
            productName = nil
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Check if package already exists
            if let project = try xcodeproj.pbxproj.rootProject(),
                project.remotePackages.contains(where: { $0.repositoryURL == packageURL })
            {
                return CallTool.Result(
                    content: [
                        .text("Swift Package '\(packageURL)' already exists in project")
                    ]
                )
            }

            // Create Swift Package reference
            let packageRef = XCRemoteSwiftPackageReference(
                repositoryURL: packageURL,
                versionRequirement: parseRequirement(requirement)
            )
            xcodeproj.pbxproj.add(object: packageRef)

            // Add to project's package references
            if let project = try xcodeproj.pbxproj.rootProject() {
                project.remotePackages.append(packageRef)
            }

            // If target name is specified, add package product to target
            if let targetName = targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Create product dependency
                let productDependency = XCSwiftPackageProductDependency(
                    productName: productName ?? "Unknown",
                    package: packageRef
                )
                xcodeproj.pbxproj.add(object: productDependency)

                // Initialize packageProductDependencies if nil
                if target.packageProductDependencies == nil {
                    target.packageProductDependencies = []
                }
                target.packageProductDependencies?.append(productDependency)
            }

            // Save project
            try xcodeproj.write(path: Path(projectURL.path))

            var message =
                "Successfully added Swift Package '\(packageURL)' with requirement '\(requirement)'"
            if let targetName = targetName {
                message += " to target '\(targetName)'"
            }

            return CallTool.Result(
                content: [
                    .text(message)
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add Swift Package to Xcode project: \(error.descriptiveMessage)")
        }
    }

    private func parseRequirement(_ requirement: String)
        -> XCRemoteSwiftPackageReference.VersionRequirement
    {
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse different requirement formats
        if trimmed.hasPrefix("from:") {
            let version = String(trimmed.dropFirst(5)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .upToNextMajorVersion(version)
        } else if trimmed.hasPrefix("upToNextMajor:") {
            let version = String(trimmed.dropFirst(14)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .upToNextMajorVersion(version)
        } else if trimmed.hasPrefix("upToNextMinor:") {
            let version = String(trimmed.dropFirst(14)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .upToNextMinorVersion(version)
        } else if trimmed.hasPrefix("branch:") {
            let branch = String(trimmed.dropFirst(7)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .branch(branch)
        } else if trimmed.hasPrefix("revision:") {
            let revision = String(trimmed.dropFirst(9)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .revision(revision)
        } else if trimmed.hasPrefix("exact:") {
            let version = String(trimmed.dropFirst(6)).trimmingCharacters(
                in: .whitespacesAndNewlines)
            return .exact(version)
        } else {
            // Default to exact version if just a version number
            return .exact(trimmed)
        }
    }
}
