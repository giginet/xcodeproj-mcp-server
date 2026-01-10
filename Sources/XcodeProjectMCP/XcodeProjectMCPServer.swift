import Foundation
import Logging
import MCP

public enum ToolName: String, CaseIterable {
    case createXcodeproj = "create_xcodeproj"
    case listTargets = "list_targets"
    case listBuildConfigurations = "list_build_configurations"
    case listFiles = "list_files"
    case getBuildSettings = "get_build_settings"
    case addFile = "add_file"
    case removeFile = "remove_file"
    case moveFile = "move_file"
    case createGroup = "create_group"
    case addTarget = "add_target"
    case removeTarget = "remove_target"
    case addDependency = "add_dependency"
    case setBuildSetting = "set_build_setting"
    case addFramework = "add_framework"
    case addBuildPhase = "add_build_phase"
    case duplicateTarget = "duplicate_target"
    case addSwiftPackage = "add_swift_package"
    case listSwiftPackages = "list_swift_packages"
    case removeSwiftPackage = "remove_swift_package"
    case listGroups = "list_groups"
    case addSynchronizedFolder = "add_synchronized_folder"
    case addAppExtension = "add_app_extension"
    case removeAppExtension = "remove_app_extension"
}

public struct XcodeProjectMCPServer {
    private let basePath: String
    private let logger: Logger

    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    public func run() async throws {
        let server = Server(
            name: "xcodeproj-mcp-server",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        let pathUtility = PathUtility(basePath: basePath)
        let createXcodeprojTool = CreateXcodeprojTool(pathUtility: pathUtility)
        let listTargetsTool = ListTargetsTool(pathUtility: pathUtility)
        let listBuildConfigurationsTool = ListBuildConfigurationsTool(pathUtility: pathUtility)
        let listFilesTool = ListFilesTool(pathUtility: pathUtility)
        let getBuildSettingsTool = GetBuildSettingsTool(pathUtility: pathUtility)
        let addFileTool = AddFileTool(pathUtility: pathUtility)
        let removeFileTool = RemoveFileTool(pathUtility: pathUtility)
        let moveFileTool = MoveFileTool(pathUtility: pathUtility)
        let createGroupTool = CreateGroupTool(pathUtility: pathUtility)
        let addTargetTool = AddTargetTool(pathUtility: pathUtility)
        let removeTargetTool = RemoveTargetTool(pathUtility: pathUtility)
        let addDependencyTool = AddDependencyTool(pathUtility: pathUtility)
        let setBuildSettingTool = SetBuildSettingTool(pathUtility: pathUtility)
        let addFrameworkTool = AddFrameworkTool(pathUtility: pathUtility)
        let addBuildPhaseTool = AddBuildPhaseTool(pathUtility: pathUtility)
        let duplicateTargetTool = DuplicateTargetTool(pathUtility: pathUtility)
        let addSwiftPackageTool = AddSwiftPackageTool(pathUtility: pathUtility)
        let listSwiftPackagesTool = ListSwiftPackagesTool(pathUtility: pathUtility)
        let removeSwiftPackageTool = RemoveSwiftPackageTool(pathUtility: pathUtility)
        let listGroupsTool = ListGroupsTool(pathUtility: pathUtility)
        let addSynchronizedFolderTool = AddFolderTool(pathUtility: pathUtility)
        let addAppExtensionTool = AddAppExtensionTool(pathUtility: pathUtility)
        let removeAppExtensionTool = RemoveAppExtensionTool(pathUtility: pathUtility)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                createXcodeprojTool.tool(),
                listTargetsTool.tool(),
                listBuildConfigurationsTool.tool(),
                listFilesTool.tool(),
                getBuildSettingsTool.tool(),
                addFileTool.tool(),
                removeFileTool.tool(),
                moveFileTool.tool(),
                createGroupTool.tool(),
                addTargetTool.tool(),
                removeTargetTool.tool(),
                addDependencyTool.tool(),
                setBuildSettingTool.tool(),
                addFrameworkTool.tool(),
                addBuildPhaseTool.tool(),
                duplicateTargetTool.tool(),
                addSwiftPackageTool.tool(),
                listSwiftPackagesTool.tool(),
                removeSwiftPackageTool.tool(),
                listGroupsTool.tool(),
                addSynchronizedFolderTool.tool(),
                addAppExtensionTool.tool(),
                removeAppExtensionTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = ToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            switch toolName {
            case .createXcodeproj:
                return try createXcodeprojTool.execute(arguments: params.arguments ?? [:])
            case .listTargets:
                return try listTargetsTool.execute(arguments: params.arguments ?? [:])
            case .listBuildConfigurations:
                return try listBuildConfigurationsTool.execute(arguments: params.arguments ?? [:])
            case .listFiles:
                return try listFilesTool.execute(arguments: params.arguments ?? [:])
            case .getBuildSettings:
                return try getBuildSettingsTool.execute(arguments: params.arguments ?? [:])
            case .addFile:
                return try addFileTool.execute(arguments: params.arguments ?? [:])
            case .removeFile:
                return try removeFileTool.execute(arguments: params.arguments ?? [:])
            case .moveFile:
                return try moveFileTool.execute(arguments: params.arguments ?? [:])
            case .createGroup:
                return try createGroupTool.execute(arguments: params.arguments ?? [:])
            case .addTarget:
                return try addTargetTool.execute(arguments: params.arguments ?? [:])
            case .removeTarget:
                return try removeTargetTool.execute(arguments: params.arguments ?? [:])
            case .addDependency:
                return try addDependencyTool.execute(arguments: params.arguments ?? [:])
            case .setBuildSetting:
                return try setBuildSettingTool.execute(arguments: params.arguments ?? [:])
            case .addFramework:
                return try addFrameworkTool.execute(arguments: params.arguments ?? [:])
            case .addBuildPhase:
                return try addBuildPhaseTool.execute(arguments: params.arguments ?? [:])
            case .duplicateTarget:
                return try duplicateTargetTool.execute(arguments: params.arguments ?? [:])
            case .addSwiftPackage:
                return try addSwiftPackageTool.execute(arguments: params.arguments ?? [:])
            case .listSwiftPackages:
                return try listSwiftPackagesTool.execute(arguments: params.arguments ?? [:])
            case .removeSwiftPackage:
                return try removeSwiftPackageTool.execute(arguments: params.arguments ?? [:])
            case .listGroups:
                return try listGroupsTool.execute(arguments: params.arguments ?? [:])
            case .addSynchronizedFolder:
                return try addSynchronizedFolderTool.execute(arguments: params.arguments ?? [:])
            case .addAppExtension:
                return try addAppExtensionTool.execute(arguments: params.arguments ?? [:])
            case .removeAppExtension:
                return try removeAppExtensionTool.execute(arguments: params.arguments ?? [:])
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
