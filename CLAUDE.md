# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pointless is a minimal, plugin-driven macOS menu bar app for system monitoring. The core philosophy is "everything is a plugin" — even built-in metrics like CPU are implemented as plugins that the app shell loads and displays.

## Build & Run

```bash
# Build the project
swift build

# Run the app
swift run

# Run tests (simple test runner without XCTest)
swift Tests/run-tests.swift

# Lint code (SwiftLint must be installed)
swiftlint
```

**Note on Testing**: Due to Swift 6.2 + Command Line Tools limitations, XCTest is not available. A standalone test runner (`Tests/run-tests.swift`) is provided that works without XCTest. For full XCTest support, install Xcode.

## Architecture

### Core Design Pattern: Autonomous Plugins

Plugins are **fully autonomous** — they manage their own timers, data fetching, and state. The app shell only provides:
1. **Registration** via `PluginRegistry`
2. **Display infrastructure** (menu bar + popover)
3. **Settings persistence** (UserDefaults)

### Plugin Lifecycle

```
Registration → Configuration → Start → [Running] → Stop
```

**On app launch** (`AppDelegate.swift`):
1. Register built-in plugins (hardcoded instances)
2. Load external plugins from `~/Library/Application Support/Pointless/Plugins/*.bundle`
3. Configure plugins with saved settings from UserDefaults
4. Start all plugins (each plugin starts its own update timer)
5. Setup menu bar UI

### Plugin Protocol (`Plugin.swift`)

All plugins conform to the `Plugin` protocol:

```swift
protocol Plugin: ObservableObject {
  var id: String { get }              // Unique ID (e.g., "pointless.cpu")
  var name: String { get }            // Display name
  var menuBarText: String { get }     // Fallback text for menu bar
  var settings: PluginSettings { get }

  func menuBarView() -> NSView?       // Custom menu bar view (optional)
  func detailView() -> AnyView        // SwiftUI view for popover
  func configure(_ values: [String: Any])
  func start()                        // Start plugin's update timer
  func stop()
}
```

**Key points:**
- Plugins use `@Published` properties to trigger UI updates
- `menuBarView()` returns `nil` to fall back to `menuBarText`
- Plugins are wrapped in `AnyPlugin` for type erasure
- Each plugin manages its own `Timer` for updates

### Plugin Views

**Menu Bar:**
- Plugins can provide custom SwiftUI views via `menuBarView()` (see `CPUPlugin` for example)
- Views are hosted in `NSHostingView` and displayed in the status bar button
- `MenuBarCombinedView` horizontally combines all plugin views with separators

**Popover:**
- Each plugin provides a SwiftUI `detailView()` shown in the popover
- Popover displays all active plugins as cards

### Plugin Settings

Settings are defined declaratively via `PluginSettings`:
- `slider`, `toggle`, `hotkey`, `text`, `dropdown`
- Settings are stored in UserDefaults with key `plugin.<id>`
- Changes trigger `configure()` which can restart timers with new values

### External Plugin Loading

External plugins must:
1. Be packaged as `.bundle` files
2. Live in `~/Library/Application Support/Pointless/Plugins/`
3. Have a principal class that conforms to `Plugin` protocol
4. Inherit from `NSObject` for Objective-C runtime compatibility

The `PluginRegistry.loadExternalPlugins()` method:
- Scans the plugins directory for `.bundle` files
- Loads bundles and instantiates principal class
- Registers plugins (with duplicate ID checking)
- Logs errors for failed bundles without crashing

## Project Structure

```
Sources/Pointless/
├── App/
│   ├── PointlessApp.swift       # SwiftUI app entry point
│   ├── AppDelegate.swift        # Plugin registration & startup
│   └── PluginRegistry.swift     # Plugin storage & loading
├── Plugins/
│   ├── Plugin.swift             # Protocol + AnyPlugin wrapper
│   ├── PluginSettings.swift     # Settings definitions
│   └── CPU/
│       └── CPUPlugin.swift      # Built-in CPU monitor
└── UI/
    ├── MenuBar.swift            # NSStatusItem management
    ├── MenuBarCombinedView.swift # Combines plugin menu bar views
    ├── PopoverView.swift        # Popover content
    └── SettingsView.swift       # App settings window
```

## Adding a New Plugin

1. **Create plugin class** conforming to `Plugin` protocol
2. **Implement required properties**: `id`, `name`, `menuBarText`, `settings`
3. **Implement views**: `menuBarView()` (optional) and `detailView()`
4. **Implement lifecycle**: `start()` creates timer, `stop()` invalidates it
5. **Register in AppDelegate**: Add to `plugins` array in `applicationDidFinishLaunching`

Example structure:
```swift
class MyPlugin: ObservableObject, Plugin {
  let id = "pointless.myplugin"
  let name = "My Plugin"

  @Published var menuBarText = "..."
  private var timer: Timer?

  func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
      self.update()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func detailView() -> AnyView {
    AnyView(Text("Plugin detail view"))
  }

  // ... other protocol methods
}
```

## Code Style

- SwiftLint enforced (see `.swiftlint.yml`)
- Line length: 120 chars (warning), 150 (error)
- No force unwrapping or force casting (error level)
- Use `isEmpty` instead of `count == 0`
- Prefer type inference over explicit `.init()`

## Design Documents

- `DESIGN.md`: Detailed architecture, plugin loading flow, future plans
- `CUSTOM_VIEWS.md`: Examples of custom menu bar views for plugins
