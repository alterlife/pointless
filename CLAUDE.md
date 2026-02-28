# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pointless is a minimal, plugin-driven macOS menu bar app for system monitoring. The core philosophy is "everything is a plugin" — even built-in metrics like CPU are implemented as plugins that the app shell loads and displays.

## Design Philosophy

### High-Quality Code & Consistent Design

1. **Follow Your Own Rules**
   - SwiftLint errors (`force_unwrapping`, `force_cast`) are non-negotiable — fix violations immediately
   - If a rule exists, the code must comply. No exceptions without documented justification.
   - **Always run `swiftlint` before committing code** — 0 violations required

2. **Swift Naming Conventions**
   - Avoid vague suffixes: `Manager`, `Helper`, `Utility`, `Handler`
   - Be specific about what something IS, not what it DOES
   - Follow Apple's patterns: `URLSession` not `URLSessionManager`
   - Type erasure wrappers use `Any` prefix: `AnyPlugin`, `AnyView`

3. **Trust the Framework**
   - SwiftUI `@Published` + `@ObservedObject` handles reactivity — don't fight it with manual updates
   - Combine subscriptions must be properly managed (stored and cancelled)
   - Let the type system work for you — avoid unnecessary casts

4. **No Duplication**
   - DRY principle: same logic should only exist once
   - Consolidate similar code paths before they diverge
   - Shared behavior goes into protocol extensions or helpers

5. **Memory Safety**
   - All Combine subscriptions must be stored in `cancellables` and properly cleaned up
   - Weak references (`[weak self]`) in closures that outlive their owner
   - Timer invalidation in `stop()` or `deinit`

6. **Declarative Over Imperative**
   - Settings, UI, and plugin definitions should be data, not code
   - Let the system generate behavior from declarations
   - Reduce manual wiring and state synchronization

## Build & Run

```bash
# Build the project
swift build

# Run the app
swift run

# Run tests (simple test runner without XCTest)
swift Tests/run-tests.swift

# Lint code (requires SwiftLint: brew install swiftlint)
swiftlint

# Auto-fix fixable issues
swiftlint --fix
```

**IMPORTANT:** Always run `swiftlint` before committing. The project must have **0 violations**.

**Note on Testing**: Due to Swift 6.2 + Command Line Tools limitations, XCTest is not available. A standalone test runner (`Tests/run-tests.swift`) is provided that works without XCTest. For full XCTest support, install Xcode.

## Logging

Pointless uses Apple's unified logging system (`os.Logger`) for all diagnostic output. Logs are sent to the system logging daemon and can be viewed in Console.app or via command-line tools.

### Log Levels

The logging system supports four levels (from most to least verbose):

- **debug**: Verbose diagnostic information (plugin updates, internal state changes)
- **info**: Normal operational messages (plugin registration, app startup)
- **warning**: Recoverable issues (duplicate plugin IDs, configuration problems)
- **error**: Failure conditions (bundle load failures, missing resources)

### Environment Variable Control

Set `POINTLESS_LOG_LEVEL` to control which logs are shown:

```bash
# Show all logs including debug messages
POINTLESS_LOG_LEVEL=debug swift run

# Default: info and above (info, warning, error)
swift run

# Only warnings and errors
POINTLESS_LOG_LEVEL=warning swift run

# Only errors
POINTLESS_LOG_LEVEL=error swift run
```

### Viewing Logs

**Console.app (GUI):**
1. Open `/Applications/Utilities/Console.app`
2. In the search bar, filter by subsystem: `com.alterlife.pointless`
3. Adjust log level filter in the toolbar (Action → Include Info Messages, Include Debug Messages)

**Command line (real-time streaming):**
```bash
# Stream all logs from Pointless
log stream --predicate 'subsystem == "com.alterlife.pointless"' --level debug

# Stream only errors
log stream --predicate 'subsystem == "com.alterlife.pointless"' --level error

# Show recent logs (last 5 minutes)
log show --predicate 'subsystem == "com.alterlife.pointless"' --last 5m
```

### Usage in Code

```swift
import OSLog

// Use default loggers
Logger.info("App started")              // ✅ Info with emoji
Logger.warning("Config issue")          // ⚠️ Warning
Logger.error("Failed to load plugin")   // ❌ Error
Logger.debug("CPU value: 42%")          // 🔍 Debug (only if enabled)

// Use specific subsystem loggers
Logger.info("Plugin registered", logger: Logger.pluginRegistry)
Logger.debug("Update triggered", logger: Logger.pluginLifecycle)
```

**Available subsystem loggers:**
- `Logger.app` - App-level events (startup, shutdown)
- `Logger.pluginRegistry` - Plugin registration and loading
- `Logger.pluginLifecycle` - Plugin lifecycle events (start, stop, updates)
- `Logger.ui` - UI-related events

**Important:** Test output in `Tests/run-tests.swift` uses `print()` directly, not the logging system. This keeps test output simple and independent of log level configuration.

## Architecture

### Core Design Pattern: Autonomous Plugins

Plugins are **fully autonomous** — they manage their own timers, data fetching, and state. The app shell only provides:
1. **Registration** via `PluginRegistry`
2. **Display infrastructure** (menu bar + menu)
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
  func detailView() -> AnyView        // SwiftUI view for menu display
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

### CRITICAL: Plugin Observation in SwiftUI

**Problem:** SwiftUI's `@ObservedObject` does NOT automatically observe objects inside arrays/collections.

**Wrong approach (will not update):**
```swift
ForEach(registry.plugins, id: \.id) { plugin in
  plugin.detailView()  // ❌ No observation binding - UI freezes!
}
```

**Correct approach (updates work):**
```swift
ForEach(registry.plugins, id: \.id) { plugin in
  ObservablePluginView(plugin: plugin) { p in  // ✅ Creates @ObservedObject binding
    p.detailView()
  }
}
```

**Why this matters:**
- When a plugin updates (e.g., CPU percentage changes), it fires `objectWillChange`
- WITHOUT `ObservablePluginView`: SwiftUI never receives the notification → UI stays frozen
- WITH `ObservablePluginView`: SwiftUI receives the notification → UI updates automatically

**Rule:** Any SwiftUI view that displays plugin data MUST wrap it in `ObservablePluginView`.

### Plugin Views

**Menu Bar:**
- Plugins can provide custom SwiftUI views via `menuBarView()` (see `CPUPlugin` for example)
- Views are hosted in `NSHostingView` and displayed in the status bar button
- `MenuBarCombinedView` horizontally combines all plugin views with separators

**CRITICAL: Menu Bar Sizing**

NSStatusItem with `variableLength` relies on `intrinsicContentSize` to determine width. SwiftUI views inside `NSHostingView` don't automatically propagate their size to the parent NSView hierarchy.

**Problem:** Without proper sizing, the menu bar text gets truncated (shows "C" instead of "CPU 15%")

**Solution:** Override `intrinsicContentSize` in `MenuBarCombinedView`:
```swift
override var intrinsicContentSize: NSSize {
  // Forward the hosting view's intrinsic size
  return hostingView?.intrinsicContentSize ?? NSSize(width: 80, height: 22)
}
```

This tells NSStatusItem how wide the view needs to be, allowing it to auto-size correctly.

**Menu Display (NSMenu - REQUIRED PATTERN):**
- **CRITICAL:** Use `NSMenu` for plugin details, NOT `NSPopover`
- **Why:** Apple's HIG specifies NSMenu for menu bar extras (standard macOS pattern)
- **Reference apps:** iStat Menus, Stats use NSMenu with embedded SwiftUI views
- Each plugin's `detailView()` is embedded in NSMenuItem via NSHostingView
- **All graphics preserved:** Icons, colors, charts, custom layouts work perfectly in menu items
- Standard menu structure:
  ```
  [Plugin Details - custom views]
  ─────────────────────
  Settings...      ⌘,
  ─────────────────────
  Quit Pointless   ⌘Q
  ```
- **Never use:** NSPopover for main UI, right-click menus, icon-based quit buttons

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
    ├── MenuBar.swift            # NSStatusItem + NSMenu management
    ├── MenuBarCombinedView.swift # Combines plugin menu bar views
    └── SettingsView.swift       # App settings window
```

## Adding a New Plugin

1. **Create plugin class** conforming to `Plugin` protocol
2. **Implement required properties**: `id`, `name`, `menuBarText`
3. **Implement views**: `menuBarView()` (optional) and `detailView()`
4. **Use lifecycle helpers**: `declareSettings()` and `setupPeriodicUpdate()` for automatic management
5. **Register in AppDelegate**: Add to `plugins` array in `applicationDidFinishLaunching`

### Plugin Lifecycle Management

Plugins automatically get lifecycle management with **zero boilerplate**:

```swift
class MyPlugin: NSObject, ObservableObject, Plugin {
  let id = "pointless.myplugin"
  let name = "My Plugin"

  @Published var menuBarText = "..."
  @Published var isEnabled = true
  @Published var updateInterval: TimeInterval = 5.0

  func initialize() {
    // Declare settings
    declareSettings([
      .slider(
        key: "updateInterval",
        label: "Update Interval",
        range: 1.0...60.0,
        defaultValue: 5.0
      )
    ])

    // Setup periodic updates
    setupPeriodicUpdate(interval: \.updateInterval) {
      self.refresh()
    }
  }

  private func refresh() {
    // Update plugin data
    menuBarText = "Updated!"
  }

  func detailView() -> AnyView {
    AnyView(Text("Plugin detail view"))
  }
}
```

**Key points:**
- **No boilerplate** - lifecycle is managed automatically via associated objects
- Use `declareSettings()` to define plugin settings
- Use `setupPeriodicUpdate()` to configure automatic timer management
- The lifecycle handles timer start/stop, interval changes, and cleanup automatically
- No need to manually manage timers or subscriptions

## Code Style

SwiftLint is enforced (see `.swiftlint.yml`). Key rules to follow:

**Strictly Enforced (errors):**
- **No force unwrapping** (`!`) - use optional binding or nil coalescing
- **No force casting** (`as!`) - use conditional casting (`as?`)
- **Line length:** 120 chars (warning), 150 chars (error)

**Best Practices (warnings):**
- Use `isEmpty` instead of `count == 0`
- Prefer type inference over explicit `.init()`
- No tuples with more than 2 members - use a struct instead
- Remove unused imports
- No duplicate imports

## Design Documents

- `DESIGN.md`: Detailed architecture, plugin loading flow, future plans
- `CUSTOM_VIEWS.md`: Examples of custom menu bar views for plugins
