# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pointless is a macOS app for cursor-free navigation. The app also has a plugin system for monitoring widgets.

## Design Philosophy

### Lint enforced Code, Consistent Design

1. **Follow Your Own Rules**
   - SwiftLint errors are non-negotiable - If a rule exists, the code must comply. 
   - Exceptions MUST be approved by the developer.
   - **Always run `swiftlint` before committing code** - 0 violations required

2. **Naming Conventions**
   - Avoid vague suffixes: `Manager`, `Helper`, `Utility`, `Handler`.
   - Follow Apple's patterns: `URLSession` not `URLSessionManager`
   - Type erasure wrappers use `Any` prefix: `AnyPlugin`, `AnyView`

3. **Don't manually do what the framework already does** For example:
   - SwiftUI `@Published` + `@ObservedObject` handles reactivity — don't fight it with manual updates
   - Let the type system work for you — avoid unnecessary casts

   Do not implement custom solutions before you have researched the framework's capabilities.

4. **No Duplication**
   - Code must be SOLID and DRY

5. **Lifetime Management**
   - Store Combine subscriptions in `cancellables`; clean them up
   - Use `[weak self]` in closures that outlive their owner
   - Invalidate timers, remove event monitors, and unregister
     notification/AX observers in `stop()`/`deinit`/`end()`

6. **Declarative Over Imperative**
   - Settings, widgets, and plugin behavior are data declarations, not code.
     New settings go in `declareSettings([...])`, new display goes in
     `menuBarWidgets()`/`menuWidgets()` — never hand-wired UI or manual
     state syncing in the app shell

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

**Note on Testing**: `swift test` runs the XCTest suite in `Tests/PointlessTests/` (requires Xcode, not just Command Line Tools). `swift Tests/run-tests.swift` is a supplementary standalone runner with self-contained mock-based tests — it does not compile `Sources/`.

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

### Core Feature: Cursor-Free Navigation

Navigation is a core feature. Since it's not a plugin, don't register it in
`PluginRegistry` or make it conform to `Plugin`. See `Navigation/`:
`KeyboardNavigation` handles hotkeys and settings; each activation runs a
`NavigationSession`.

### Plugin System

Plugins manage their own timers, data fetching, and state. The app shell provides:
1. **Registration** via `PluginRegistry`
2. **Display infrastructure** (menu bar + menu via `WidgetRegistry`)
3. **Settings persistence** (UserDefaults)

### Plugin Lifecycle

```
Registration → Configuration → Start → [Running] → Stop
```

**On app launch** (`AppDelegate.swift`):
1. Start `KeyboardNavigation` (hotkeys, permission onboarding) and register its widgets
2. Register built-in plugins (hardcoded instances)
3. Load external plugins from `~/Library/Application Support/Pointless/Plugins/*.bundle`
4. Start all plugins (each plugin starts its own update timer)
5. Setup menu bar UI and screen sleep/wake monitoring

### Plugin Protocol (`Plugin.swift`)

All plugins conform to the `Plugin` protocol:

```swift
protocol Plugin: ObservableObject {
  var id: String { get }              // Unique ID (e.g., "pointless.cpu")
  var name: String { get }            // Display name
  var icon: String { get }            // SF Symbol for settings tab
  var isEnabled: Bool { get set }     // Plugins ship disabled by default

  func initialize()                   // One-time setup in init
  func settings() -> PluginSettings   // Declarative settings definitions
  func configure(with values: [String: Any])
  func start()                        // Start plugin's update timer
  func stop()
  func suspend()                      // Screen sleep
  func resume()                       // Screen wake
  func menuBarWidgets() -> [MenuBarWidget]
  func menuWidgets() -> [MenuWidget]
}
```

**Key points:**
- Plugins use `@Published` properties to trigger UI updates
- Plugins are wrapped in `AnyPlugin` for type erasure
- Each plugin manages its own `Timer` for updates via `PluginLifecycle`
- Display goes through `menuBarWidgets()`/`menuWidgets()` — the widget registry
  owns ordering, visibility, and drag-to-reorder in Settings

### CRITICAL: Plugin Observation in SwiftUI

**Problem:** SwiftUI's `@ObservedObject` does NOT automatically observe objects inside arrays/collections.

**Rule:** Any SwiftUI view that displays plugin data MUST be wrapped in `ObservableWidgetView` (menu bar and menu widgets) or `ObservablePluginView` (direct plugin content). Without an observation binding, the UI freezes after the initial render.

### Plugin Views

All plugin display goes through widgets — `menuBarWidgets()` for the status bar, `menuWidgets()` for the dropdown menu. Views are SwiftUI, hosted in `NSHostingView`; `MenuBarCombinedView` lays out menu bar widgets horizontally with separators.

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
- Each `MenuWidget`'s view is embedded in an NSMenuItem via NSHostingView
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
- `slider`, `toggle`, `hotkey`, `text`, `dropdown`, `color`, `section`
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

The core product is cursor-free navigation ("pointless" = pointer-less). It lives in
`Navigation/` as an app-level feature, NOT a plugin. The plugin system carries optional
monitoring widgets only, and plugins ship disabled by default.

```
Sources/Pointless/
├── App/
│   ├── AppDelegate.swift            # Starts navigation, registers plugins
│   ├── PluginRegistry.swift         # Plugin storage & external bundle loading
│   ├── ScreenStateMonitor.swift     # Sleep/wake suspend-resume
│   └── Logger.swift                 # os.Logger wrappers
├── AX/
│   └── AXElement.swift              # Typed facade over AXUIElement — ALL raw AX
│                                    #   calls and CF cast workarounds live here
├── Navigation/                      # CORE FEATURE: cursor-free navigation
│   ├── KeyboardNavigation.swift     # Controller: hotkeys, settings, monitors
│   ├── NavigationSession.swift      # One activation: scan→overlay→input→click
│   ├── ElementOverlay.swift         # Overlay windows + badge rendering
│   ├── LabelGenerator.swift         # Letter-label assignment (pure)
│   ├── ShortcutParsing.swift        # Hotkey string parsing (pure)
│   ├── KeyboardOnboarding.swift     # AX + Input Monitoring permissions
│   ├── NavigationMenuWidgetView.swift
│   └── Discovery/                   # Element discovery pass pipeline
│       ├── ElementDiscovery.swift   # Orchestrator + cross-pass dedup
│       ├── DiscoveryPass.swift      # Pass protocol + shared tree walker
│       ├── TreeWalkPass.swift       # Normal AX traversal
│       ├── FocusedElementFallbackPass.swift  # Broken window trees (Firefox)
│       ├── HitTestPass.swift        # Opaque web content (Safari Start Page)
│       └── DiscoveredElement.swift
├── Core/
│   ├── SettingsHost.swift           # Settings abstraction (navigation + plugins)
│   ├── Widget.swift                 # MenuBarWidget / MenuWidget
│   └── WidgetRegistry.swift
├── Plugins/                         # OPTIONAL monitoring (off by default)
│   ├── Plugin.swift                 # Protocol + AnyPlugin wrapper
│   ├── PluginSettings.swift         # Declarative settings definitions
│   ├── PluginLifecycle.swift        # Timer/suspend lifecycle
│   ├── PluginDefaultImplementations.swift  # declareSettings/setupPeriodicUpdate
│   └── CPU/                         # Built-in CPU monitor
└── UI/
    ├── MenuBar.swift                # NSStatusItem + NSMenu management
    ├── MenuBarCombinedView.swift
    ├── SettingsView.swift           # Renders SettingsHost definitions
    ├── SettingsViewHelpers.swift    # Setting renderers + persistence
    ├── SettingsWindowManager.swift  # Single settings window
    ├── WidgetDragDelegates.swift    # Drag-to-reorder drop delegates
    ├── ObservableWidgetView.swift
    └── ColorExtensions.swift        # Hex color helpers
```

**New app quirks in element discovery become new `DiscoveryPass` implementations,
not edits to existing passes.** Raw `AXUIElement` calls outside `AX/AXElement.swift`
are forbidden — extend the facade instead.

## Adding a New Plugin

1. **Create plugin class** conforming to `Plugin` protocol
2. **Implement required properties**: `id`, `name`, `isEnabled` (`icon` has a default)
3. **Implement display**: `menuBarWidgets()` and/or `menuWidgets()` — return
   `MenuBarWidget`/`MenuWidget` with SwiftUI view builders
4. **Use lifecycle helpers**: `declareSettings()` and `setupPeriodicUpdate()` for automatic management
5. **Register in AppDelegate**: Add to `plugins` array in `applicationDidFinishLaunching`

### Plugin Lifecycle Management

Plugins automatically get lifecycle management with **zero boilerplate**:

```swift
class MyPlugin: NSObject, ObservableObject, Plugin {
  let id = "pointless.myplugin"
  let name = "My Plugin"

  @Published var isEnabled = false  // plugins ship disabled
  @Published var updateInterval: TimeInterval = 5.0

  func initialize() {
    declareSettings([
      .slider(
        key: "updateInterval",
        label: "Update Interval",
        range: 1.0...60.0,
        defaultValue: 5.0
      )
    ])

    setupPeriodicUpdate(interval: \.updateInterval) {
      self.refresh()
    }
  }

  func configure(with values: [String: Any]) {
    if let enabled = values["enabled"] as? Bool { isEnabled = enabled }
    if let interval = values["updateInterval"] as? TimeInterval { updateInterval = interval }
    saveSettings(values)
  }

  private func refresh() {
    // Update plugin data
  }

  func menuBarWidgets() -> [MenuBarWidget] {
    [
      MenuBarWidget(id: "\(id).menubar", ownerId: id, name: "My Plugin", priority: 100) {
        Text("MP")
      }
    ]
  }
}
```
```

**Key points:**
- **No boilerplate** - lifecycle is managed automatically via associated objects
- Use `declareSettings()` to define plugin settings
- Use `setupPeriodicUpdate()` to configure automatic timer management
- The lifecycle handles timer start/stop, interval changes, and cleanup automatically
- No need to manually manage timers or subscriptions

## Code Style

SwiftLint is enforced (see `.swiftlint.yml`).

## Documentation Guidance

1. **Be Honest and Grounded**
   - Never oversell or make hyperbolic claims.
   - Accurately describe algorithmic behavior and limitations.

2. **Don't Say Things You Don't Have To**
   - Avoid marketing buzzwords, self-congratulatory adjectives, and redundant implementation details.
   - Docs do not need to sell the product or drown the reader in detail — keep explanations direct, clean, and factual.

3. **Reader-First Perspective**
   - Focus on what the reader or contributor needs to know that cannot be easily deduced from reading the code:

## Design Documents

- `IMPROVEMENTS.md`: Improvement plan — UX, code cleanliness, maintenance proposals
