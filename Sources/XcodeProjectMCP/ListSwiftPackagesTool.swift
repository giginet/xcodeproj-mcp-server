import Foundation
import MCP
import PathKit
import XcodeProj

public struct ListSwiftPackagesTool: Sendable {
    private let pathUtility: PathUtility
    private let projectLoader: ProjectLoader

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
        self.projectLoader = ProjectLoader(pathUtility: pathUtility)
    }

    public func tool() -> Tool {
        Tool(
            name: "list_swift_packages",
            description: "List all Swift Package dependencies in an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ])
                ]),
                "required": .array([.string("project_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        do {
            let (loadedProject, _) = try projectLoader.load(projectPath: projectPath)

            var packages: [String] = []
            switch loadedProject {
            case .pbxproj(let xcodeproj):
                guard let project = try xcodeproj.pbxproj.rootProject() else {
                    throw MCPError.internalError("Unable to access project root")
                }

                // List remote packages
                for remotePackage in project.remotePackages {
                    let requirement = formatVersionRequirement(
                        remotePackage.versionRequirement ?? .exact("unknown"))
                    let url = remotePackage.repositoryURL ?? "unknown"
                    packages.append("📦 \(url) (\(requirement))")
                }

                // List local packages
                for localPackage in project.localPackages {
                    packages.append("📁 \(localPackage.relativePath) (local)")
                }
            case .xcproj(let file):
                packages = XCProjSupport.packageDescriptions(of: file.project)
            }

            if packages.isEmpty {
                return CallTool.Result(
                    content: [
                        .text("No Swift Package dependencies found in project")
                    ]
                )
            }

            let packageList = packages.joined(separator: "\n")
            return CallTool.Result(
                content: [
                    .text("Swift Package dependencies:\n\(packageList)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to list Swift Packages in Xcode project: \(error.descriptiveMessage)")
        }
    }

    private func formatVersionRequirement(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement
    )
        -> String
    {
        switch requirement {
        case let .exact(version):
            return "exact: \(version)"
        case let .upToNextMajorVersion(version):
            return "from: \(version)"
        case let .upToNextMinorVersion(version):
            return "upToNextMinor: \(version)"
        case let .range(from, to):
            return "range: \(from) - \(to)"
        case let .branch(branch):
            return "branch: \(branch)"
        case let .revision(revision):
            return "revision: \(revision)"
        }
    }
}
