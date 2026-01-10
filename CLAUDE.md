# xcodeproj-mcp-server

A Model Context Protocol (MCP) server for manipulating Xcode project files (.xcodeproj) using Swift.

## Overview

This project provides an MCP server that enables interaction with Xcode projects through a standardized protocol. It leverages the [tuist/xcodeproj](https://github.com/tuist/xcodeproj) library for project manipulation and the [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP functionality.

## Architecture

- **Language**: Swift
- **Platform**: macOS 13+
- **Dependencies**:
  - ModelContextProtocol (MCP Swift SDK)
  - XcodeProj (Xcode project manipulation)

## Package Structure

The project is organized into multiple targets for better modularity and testability:

```
xcodeproj-mcp-server/
├── Package.swift
├── Sources/
│   ├── XcodeProjectMCP/           # Library target
│   │   ├── XcodeProjectMCPServer.swift
│   │   ├── CreateXcodeprojTool.swift
│   │   └── [other tool implementations]
│   └── xcodeproj-mcp-server/      # Executable target
│       └── main.swift
├── Tests/
│   └── XcodeProjectMCPTests/      # Test target
│       └── CreateXcodeprojToolTests.swift
└── CLAUDE.md
```

### Targets

- **XcodeProjectMCP** (Library): Core functionality and MCP tools
  - Contains all tool implementations
  - Provides the main server class
  - Can be imported by other Swift packages

- **xcodeproj-mcp-server** (Executable): Command-line interface
  - Minimal main.swift that starts the server
  - Depends on XcodeProjectMCP library

- **XcodeProjectMCPTests** (Test): Unit tests
  - Tests for tool implementations
  - Integration tests for MCP functionality
  - All tests are written using swift-testing framework

## Available Tools

### Core Operations
- `create_xcodeproj` - Create a new Xcode project with basic configuration
- `list_targets` - List all targets in an Xcode project
- `list_build_configurations` - List all build configurations
- `list_files` - List all files in a specific target
- `get_build_settings` - Get build settings for a specific target

### File Management
- `add_file` - Add a file to the Xcode project
- `remove_file` - Remove a file from the Xcode project
- `move_file` - Move or rename a file within the project
- `create_group` - Create a new group in the project navigator

### Target Management
- `add_target` - Create a new target
- `remove_target` - Remove an existing target
- `add_dependency` - Add dependency between targets
- `set_build_setting` - Modify build settings for a target

### App Extension Management
- `add_app_extension` - Add an App Extension target and embed it in a host app (Widget, Push Notification, Share, etc.)
- `remove_app_extension` - Remove an App Extension target and its embedding from the host app

### Advanced Operations
- `add_framework` - Add framework dependencies
- `add_build_phase` - Add custom build phases
- `duplicate_target` - Duplicate an existing target

## Implementation Status

✅ **Completed**:
- Project initialization
- Package.swift with dependencies
- Basic MCP server structure
- All tool implementations (except open_xcodeproj which was removed for container compatibility)
- Comprehensive error handling and validation
- Complete unit test suite using swift-testing framework
- PathUtility for secure path handling within base directory constraints

## Building and Running

```bash
# Build the project
swift build

# Run the MCP server
swift run xcodeproj-mcp-server
```

## Usage Example

The server responds to MCP tool calls. Example of creating a new Xcode project:

```json
{
  "tool": "create_xcodeproj",
  "arguments": {
    "project_name": "MyApp",
    "path": "/path/to/projects",
    "organization_name": "My Company",
    "bundle_identifier": "com.mycompany"
  }
}
```

## Development Notes

- Each tool is implemented as a separate Swift file in the Sources directory
- Tools conform to the `Tool` protocol from ModelContextProtocol
- XcodeProj library handles the low-level .xcodeproj file manipulation
- Error handling uses custom ToolError enum for consistent error reporting
- **Testing**: All tests are written using swift-testing framework instead of XCTest for modern Swift testing capabilities
- **Development Rule**: Always run `swift test` after implementing new features to verify tests pass
- Execute `swift format -r -i .` to format the codebase before committing changes
