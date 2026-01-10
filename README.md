# xcodeproj-mcp-server

![GitHub Workflow Status (with event)](https://img.shields.io/github/actions/workflow/status/giginet/xcodeproj-mcp-server/tests.yml?style=flat-square&logo=github)
![Swift 6.1](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&style=flat-square)
[![Xcode 16.4](https://img.shields.io/badge/Xcode-16.4-16C5032a?style=flat-square&logo=xcode&link=https%3A%2F%2Fdeveloper.apple.com%2Fxcode%2F)](https://developer.apple.com/xcode/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-green?logo=swift&style=flat-square)](https://swift.org/package-manager/) 
![Platforms](https://img.shields.io/badge/Platform-macOS-lightgray?logo=apple&style=flat-square)
[![License](https://img.shields.io/badge/License-MIT-darkgray?style=flat-square)
](https://github.com/giginet/xcodeproj-mcp-server/blob/main/LICENSE.md)

A Model Context Protocol (MCP) server for manipulating Xcode project files (.xcodeproj) using Swift.

![Adding Post Build Phase for all targets](Documentation/demo.png)

## Overview

xcodeproj-mcp-server is an MCP server that provides tools for programmatically manipulating Xcode project files. It leverages the [tuist/xcodeproj](https://github.com/tuist/xcodeproj) library for reliable project file manipulation and implements the Model Context Protocol using the [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk).

This server enables AI assistants and other MCP clients to:
- Create new Xcode projects
- Manage targets, files, and build configurations
- Inspect project structure including groups and hierarchies
- Modify build settings
- Add dependencies and frameworks
- Automate common Xcode project tasks

## Use Cases

### Project Creation and Setup
- **Create projects from scratch**: Generate new Xcode projects with custom configurations, bundle identifiers, and organization settings without opening Xcode
- **Multi-target project scaffolding**: Set up complex projects with multiple apps, frameworks, tests, and extensions in a single automated workflow

### Development Workflow Automation
- **Add new files to targets**: After creating a new Swift file, automatically add it to the appropriate target's source files for compilation
- **Add folder references**: Include external resource folders or asset directories as synchronized folder references in your project, automatically reflecting any file system changes
- **Add build phases**: Integrate code formatters, linters, or custom build scripts into your targets (e.g., SwiftLint, SwiftFormat execution phases)
- **Create frameworks and app extensions**: Quickly scaffold new framework targets or app extensions for modularizing your codebase

### Project Configuration Management
- **Automate Info.plist setup**: Programmatically configure Info.plist settings, entitlements, and provisioning profiles for different targets
- **Build configuration management**: Set up different build configurations with appropriate compiler flags, bundle identifiers, and deployment targets
- **Dependency management**: Add system frameworks, link libraries, and configure target dependencies without manual Xcode navigation

## How to set up for Claude Desktop and Claude Code

### Prerequisites

- Docker
- macOS (for running Xcode projects)

### Installation using Docker

Pull the pre-built Docker image from GitHub Container Registry:

```bash
docker pull ghcr.io/giginet/xcodeproj-mcp-server
```

### Configuration for Claude Code

```bash
# Add MCP server using Docker
$ claude mcp add xcodeproj -- docker run --rm -i -v $PWD:/workspace ghcr.io/giginet/xcodeproj-mcp-server /workspace
```

We need to mount the current working directory (`$PWD`) to `/workspace` inside the container. This allows the server to access your Xcode projects.

### Configuration for Claude Desktop

Add the following to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "xcodeproj": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "-v",
        "${workspaceFolder}:/workspace",
        "ghcr.io/giginet/xcodeproj-mcp-server",
        "/workspace"
      ]
    }
  }
}
```

### Path Security

The MCP server now supports restricting file operations to a specific base directory. When you provide a base path as a command-line argument:

- All `project_path` and file path parameters will be resolved relative to this base path
- Absolute paths are validated to ensure they're within the base directory
- Any attempt to access files outside the base directory will result in an error

This is especially useful when running the server in Docker containers or other sandboxed environments.

## Available Tools

### Project Management

- **`create_xcodeproj`** - Create a new Xcode project
  - Parameters: `project_name`, `path`, `organization_name`, `bundle_identifier`

- **`list_targets`** - List all targets in a project
  - Parameters: `project_path`

- **`list_build_configurations`** - List all build configurations
  - Parameters: `project_path`

- **`list_files`** - List all files in a specific target
  - Parameters: `project_path`, `target_name`

- **`list_groups`** - List all groups in the project with hierarchical paths, optionally filtered by target
  - Parameters: `project_path`, `target_name` (optional)

### File Operations

- **`add_file`** - Add a file to the project
  - Parameters: `project_path`, `file_path`, `target_name`, `group_path`

- **`remove_file`** - Remove a file from the project
  - Parameters: `project_path`, `file_path`

- **`move_file`** - Move or rename a file within the project
  - Parameters: `project_path`, `source_path`, `destination_path`

- **`add_synchronized_folder`** - Add a synchronized folder reference to the project
  - Parameters: `project_path`, `folder_path`, `group_name`, `target_name`

- **`create_group`** - Create a new group in the project navigator
  - Parameters: `project_path`, `group_name`, `parent_group_path`

### Target Management

- **`add_target`** - Create a new target
  - Parameters: `project_path`, `target_name`, `type`, `platform`, `bundle_identifier`

- **`remove_target`** - Remove an existing target
  - Parameters: `project_path`, `target_name`

- **`duplicate_target`** - Duplicate an existing target
  - Parameters: `project_path`, `source_target_name`, `new_target_name`

- **`add_dependency`** - Add dependency between targets
  - Parameters: `project_path`, `target_name`, `dependency_name`

### App Extension Management

- **`add_app_extension`** - Add an App Extension target and embed it in a host app
  - Parameters: `project_path`, `extension_name`, `extension_type`, `host_target_name`, `bundle_identifier`, `platform` (optional), `deployment_target` (optional)
  - Supported extension types: `widget`, `notification_service`, `notification_content`, `share`, `today`, `action`, `file_provider`, `intents`, `intents_ui`, `keyboard`, `photo_editing`, `document_provider`, `custom`

- **`remove_app_extension`** - Remove an App Extension target and its embedding from the host app
  - Parameters: `project_path`, `extension_name`

### Build Configuration

- **`get_build_settings`** - Get build settings for a target
  - Parameters: `project_path`, `target_name`, `configuration_name`

- **`set_build_setting`** - Modify build settings
  - Parameters: `project_path`, `target_name`, `setting_name`, `value`, `configuration_name`

- **`add_framework`** - Add framework dependencies
  - Parameters: `project_path`, `target_name`, `framework_name`, `embed`

- **`add_build_phase`** - Add custom build phases
  - Parameters: `project_path`, `target_name`, `phase_type`, `name`, `script`

### Swift Package Management

- **`add_swift_package`** - Add a Swift Package dependency to the project
  - Parameters: `project_path`, `package_url`, `requirement`, `target_name`, `product_name`

- **`list_swift_packages`** - List all Swift Package dependencies in the project
  - Parameters: `project_path`

- **`remove_swift_package`** - Remove a Swift Package dependency from the project
  - Parameters: `project_path`, `package_url`, `remove_from_targets`


## License

This project is licensed under the MIT License.

