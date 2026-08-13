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
- **Add Widget Extensions**: Automatically create and embed Widget Extension targets with proper configuration for iOS home screen widgets

### Project Configuration Management
- **Automate Info.plist setup**: Programmatically configure Info.plist settings, entitlements, and provisioning profiles for different targets
- **Build configuration management**: Set up different build configurations with appropriate compiler flags, bundle identifiers, and deployment targets
- **Dependency management**: Add system frameworks, link libraries, and configure target dependencies without manual Xcode navigation

## How to set up for Claude Desktop and Claude Code

### Prerequisites

- macOS (for running Xcode projects)
- A container runtime — either [Apple's `container`](#setup-with-apples-container-recommended) (recommended) or [Docker](#setup-with-docker)

The server is distributed as a `linux/arm64` container image, which runs on either runtime.

### Setup with Apple's `container` (recommended)

[`container`](https://github.com/apple/container) is Apple's own tool for running Linux containers as lightweight virtual machines on macOS. It is the recommended runtime for this server: it comes from Apple, requires no third-party desktop application, and runs the published `linux/arm64` image natively on Apple silicon.

#### Requirements

- A Mac with Apple silicon
- macOS 26 or later (`container` does not support older versions)

#### Installation

Install the `container` CLI from the [official release page](https://github.com/apple/container/releases).

`container` needs its background service running. Start it once after installing, and again after each reboot:

```bash
container system start
```

Then pull the pre-built image from GitHub Container Registry:

```bash
container image pull ghcr.io/giginet/xcodeproj-mcp-server:latest
```

`container run` has no `--pull` option, so run `container image pull` again whenever you want to update to the latest image.

#### Configuration for Claude Code

```bash
claude mcp add xcodeproj -- container run --rm -i -v $PWD:/workspace ghcr.io/giginet/xcodeproj-mcp-server:latest /workspace
```

We need to mount the current working directory (`$PWD`) to `/workspace` inside the container. This allows the server to access your Xcode projects.

#### Configuration for Claude Desktop

Add the following to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "xcodeproj": {
      "command": "/usr/local/bin/container",
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

The installer places the binary at `/usr/local/bin/container`. The absolute path is used here because that directory is not always on the `PATH` of GUI applications.

#### Building the image locally

`container build` reads the same `Dockerfile`:

```bash
container build -t xcodeproj-mcp-server:local .
```

The builder container defaults to 2 CPUs and 2 GB of memory. Allocate more to it to speed up the release build:

```bash
container build -c 8 -m 8g -t xcodeproj-mcp-server:local .
```

### Setup with Docker

Use Docker if you are on macOS 15 or earlier, or if Docker is already part of your workflow.

Pull the pre-built Docker image from GitHub Container Registry:

```bash
docker pull ghcr.io/giginet/xcodeproj-mcp-server
```

#### Configuration for Claude Code

```bash
claude mcp add xcodeproj -- docker run --pull=always --rm -i -v $PWD:/workspace ghcr.io/giginet/xcodeproj-mcp-server:latest /workspace
```

As with `container`, the current working directory (`$PWD`) is mounted to `/workspace` inside the container so that the server can access your Xcode projects.

#### Configuration for Claude Desktop

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

### Recommended settings for Claude Code

Enabling `ENABLE_TOOL_SEARCH` in `.claude/settings.json` activates dynamic MCP tool loading. This prevents unused MCP tools from consuming context.

```json
{
  "env": {
    "ENABLE_TOOL_SEARCH": "1"
  }
}
```

### Path Security

The MCP server now supports restricting file operations to a specific base directory. When you provide a base path as a command-line argument:

- All `project_path` and file path parameters will be resolved relative to this base path
- Absolute paths are validated to ensure they're within the base directory
- Any attempt to access files outside the base directory will result in an error

This is especially useful when running the server in containers or other sandboxed environments.

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

