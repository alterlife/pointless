# Pointless Design Document

> A minimal, plugin-driven macOS system monitor by Alterlife Creations.

---

## 1. Vision

Pointless is a menu bar app that monitors system metrics. The core app does almost nothing on its own — it's a **shell** that loads plugins, polls them, and displays their output. Even built-in metrics like CPU and Memory are plugins.

**Guiding principles:**
- Minimal resource footprint
- Everything is a plugin
- Easy for others to extend

---

## 2. User Experience

### Menu Bar
- A single menu bar item displays a compact summary from active plugins
- Example: `CPU 45% | RAM 8.2G`
- **Note:** The menu bar formatter itself could be a plugin (allowing users to customize what appears and how it's formatted)
- No dock icon (the app lives entirely in the menu bar)

### Popover
- Clicking the menu bar item opens a popover
- The popover shows a **card** for each active plugin
- Each plugin controls what its card looks like
- A gear icon at the bottom opens settings

### Settings
- Toggle plugins on/off
- Adjust per-plugin refresh intervals
- (Future) Reorder plugins, customize menu bar format

---

## 3. Architecture

```
┌──────────────────────────────────────┐
│              Pointless                │
│                                      │
│  ┌──────────┐  ┌──────────────────┐  │
│  │ Plugin   │  │   UI Shell       │  │
│  │ Manager  │──│  (Menu Bar +     │  │
│  │          │  │   Popover)       │  │
│  └────┬─────┘  └──────────────────┘  │
│       │                              │
│  ┌────┴─────┐                        │
│  │ Plugin   │                        │
│  │ Scheduler│                        │
│  └────┬─────┘                        │
│       │                              │
│       ▼                              │
│  ┌────────────┐  ┌─────────────┐    │
│  │CPU Plugin  │  │Memory Plugin│ ...│
│  └────────────┘  └─────────────┘    │
└──────────────────────────────────────┘
         ▲
         │ .bundle files
┌────────┴─────────┐
│ External Plugins │
│ (user-installed) │
└──────────────────┘
```

### Components

| Component | Responsibility |
|-----------|---------------|
| **App Shell** | NSStatusItem, NSPopover, SwiftUI host. No metric logic. |
| **PluginManager** | Discovers, loads, and registers plugins. |
| **PluginScheduler** | Runs per-plugin timers, calls `refresh()`, publishes updates. |
| **Built-in Plugins** | CPU, Memory — compiled into the app, registered at startup. |
| **External Plugins** | `.bundle` files loaded from a user directory at runtime. |

---

## 4. Plugin Protocol

```swift
public struct PluginMetadata {
    public let id: String              // "pointless.cpu"
    public let name: String            // "CPU"
    public let icon: String            // SF Symbol name
    public let defaultInterval: TimeInterval
}

@objc public protocol MonitorPlugin: NSObjectProtocol {
    var metadata: PluginMetadata { get }
    func menuBarSummary() -> String    // "CPU 42%"
    func refresh()                     // fetch latest data
    func detailView() -> AnyView       // SwiftUI card content
}
```

The plugin protocol is defined in the app itself — external plugins just need to conform to it.

---

## 5. Plugin Manager — The Core

The PluginManager is responsible for the entire plugin lifecycle: discovery, loading, registration, and providing access to active plugins.

### Plugin Registry

```swift
class PluginManager: ObservableObject {
    @Published private(set) var plugins: [String: MonitorPlugin] = [:]
    @Published private(set) var activePlugins: [String] = []  // IDs of enabled plugins

    // Access plugins by ID
    func plugin(for id: String) -> MonitorPlugin?

    // Enable/disable plugins
    func enable(pluginID: String)
    func disable(pluginID: String)
}
```

### Plugin Sources

| Source | Path | When |
|--------|------|------|
| Built-in | Compiled into app binary | App startup |
| User-installed | `~/Library/Application Support/Pointless/Plugins/*.bundle` | App startup + hot-reload |

### Loading Flow

**At app startup:**

1. **Register built-in plugins** — hardcoded instances (CPU, Memory, KeyboardNav)
   ```swift
   func registerBuiltins() {
       register(CPUPlugin())
       register(MemoryPlugin())
       register(KeyboardNavPlugin())
   }
   ```

2. **Scan for external bundles** — iterate `.bundle` files in user directory
   ```swift
   let pluginsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
       .first!.appendingPathComponent("Pointless/Plugins")
   let bundles = try FileManager.default.contentsOfDirectory(at: pluginsDir, ...)
       .filter { $0.pathExtension == "bundle" }
   ```

3. **Load each bundle**
   ```swift
   guard let bundle = Bundle(url: bundleURL),
         bundle.load(),
         let principalClass = bundle.principalClass as? MonitorPlugin.Type else {
       // Log error, skip this bundle
       return
   }
   let plugin = principalClass.init()
   register(plugin)
   ```

4. **Validate & register** — check for ID conflicts, store in registry

### Plugin Lifecycle

```
Discovered → Loaded → Registered → Enabled → Scheduled
                ↓                      ↓
              Failed              Disabled (user setting)
```

- **Discovered:** Found on disk or compiled-in
- **Loaded:** Bundle loaded (external) or instantiated (built-in)
- **Registered:** Added to plugin registry with unique ID
- **Enabled:** User preference (default: all enabled)
- **Scheduled:** PluginScheduler creates timer and starts polling

### Error Handling

- Bundle fails to load → log warning, skip, don't crash
- Duplicate plugin ID → log warning, keep first, reject duplicate
- Plugin crashes during `refresh()` → catch, disable plugin, show user notification
- Missing permissions (e.g., Accessibility for KeyboardNav) → plugin shows setup instructions in detail view

### Hot Reload (Future)

Use `FSEventStream` to watch the plugins directory:
- New `.bundle` appears → load and register
- Existing `.bundle` modified → unload, reload
- `.bundle` deleted → unregister and disable

---

## 6. Scheduling & Performance

- Each plugin gets its own `DispatchSourceTimer`
- Default interval: **5 seconds** (configurable per-plugin)
- `refresh()` runs on a background queue
- Results published to main queue for UI updates
- Menu bar string updates are **coalesced** (debounced to 1s) to avoid flicker
- Popover views are **lazy** — only created when the popover is visible

---

## 7. Built-in Plugins

### CPU Plugin
- **Data source:** `host_processor_info()` (Mach API)
- **Metric:** User + system CPU % (delta between samples)
- **Menu bar:** `CPU 42%`
- **Detail view:** Per-core usage bars

### Memory Plugin
- **Data source:** `host_statistics64()`, `sysctl` for total RAM
- **Metric:** Used / total physical memory
- **Menu bar:** `RAM 8.2/16G`
- **Detail view:** Breakdown (active, wired, compressed, free)

### Keyboard Navigation Plugin
- **Purpose:** Homerow-style universal keyboard navigation for macOS
- **Functionality:**
  - Activate with a hotkey (e.g., Cmd+Shift+Space)
  - Overlay labels appear on all clickable UI elements system-wide
  - Type the label characters to click that element
  - Works across all apps via Accessibility API
- **Menu bar:** Shows activation status or shortcut hint
- **Detail view:** Settings for hotkey, label style, excluded apps, performance stats
- **Requirements:**
  - Accessibility permissions
  - Event tap for global keyboard monitoring
  - Window server overlay for label rendering

---

## 8. Project Structure

```
pointless/
├── Package.swift
├── Sources/
│   └── Pointless/
│       ├── PointlessApp.swift
│       ├── AppDelegate.swift
│       ├── Plugin/
│       │   ├── MonitorPlugin.swift     # Protocol definition
│       │   ├── PluginManager.swift
│       │   └── PluginScheduler.swift
│       ├── Plugins/                    # Built-in plugins
│       │   ├── CPUPlugin.swift
│       │   ├── MemoryPlugin.swift
│       │   └── KeyboardNavPlugin.swift
│       └── Views/
│           ├── PopoverView.swift
│           ├── PluginCardView.swift
│           └── SettingsView.swift
└── DESIGN.md
```

---

## 9. Open Questions

> These are decisions we should make before or during implementation.

- [ ] **Menu bar format** — Should users be able to customize what appears in the menu bar? (e.g., icons only, text only, pick which plugins show)
- [ ] **Plugin hot-reload** — Should we watch the plugins directory for changes and load new plugins without restarting?
- [ ] **Plugin sandboxing** — Any restrictions on what plugins can do? (network, file access, etc.)
- [ ] **Data persistence** — Should plugins be able to store historical data? If so, where?
- [ ] **First-run experience** — What happens when the app launches for the first time?
- [ ] **Distribution** — How will this be distributed? (Direct download, Homebrew, App Store?)

---

## 10. Implementation Phases

### Phase 1 — Walking skeleton
- Package.swift, app shell, NSStatusItem + NSPopover
- Plugin protocol definition
- PluginManager with built-in plugin registration
- One working plugin (CPU)

### Phase 2 — Core functionality
- PluginScheduler with per-plugin timers
- Memory plugin
- Popover with plugin cards
- Menu bar summary from active plugins

### Phase 3 — Plugin loading
- Bundle-based external plugin loading
- Example external plugin (Disk)
- Plugin directory creation on first run

### Phase 4 — Settings & polish
- Settings view (enable/disable, intervals)
- User preferences persistence
- Edge cases (no plugins, plugin errors, graceful degradation)

---

*Last updated: 2026-02-09*
