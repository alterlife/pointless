# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pointless is a minimal, plugin-driven macOS menu bar app for system monitoring. The core philosophy is "everything is a plugin" — even built-in metrics like CPU are implemented as plugins that the app shell loads and displays.

## Design Philosophy

### High-Quality Code & Consistent Design

1. **Follow Your Own Rules**
   - SwiftLint errors (`force_unwrapping`, `force_cast`) are non-negotiable — fix violations immediately
   - If a rule exists, the code must comply. No exceptions without documented justification.

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
