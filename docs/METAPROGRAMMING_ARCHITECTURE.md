# Metaprogramming Architecture: Declarative Plugin System

## Core Principle

**Plugins should declare WHAT they do, not HOW they do it.** Timer management, lifecycle, and configuration are cross-cutting concerns that should be handled through metaprogramming, not manual boilerplate.

**The framework controls timing. Plugins react to framework-driven updates.**

---

## Design: Property Wrapper + Macro Combination

### 1. @PeriodicUpdate Property Wrapper

**Purpose:** Encapsulate timer lifecycle, main run loop scheduling, and automatic reconfiguration. Interval is controlled by bound setting property.

```swift
// Sources/Pointless/Plugins/PropertyWrappers/PeriodicUpdate.swift

import Foundation
import Combine

/// Property wrapper that manages periodic timer execution with framework-controlled intervals.
///
/// The interval is controlled by binding to a setting property (typically @PluginSetting).
/// When the bound property changes, the timer automatically reconfigures.
///
/// Usage:
/// ```
/// class CPUPlugin: ObservableObject, Plugin {
///   @PluginSetting(key: "updateInterval", label: "Update Interval", range: 1.0...60.0)
///   var updateInterval: Double = 2.0
///
///   @PeriodicUpdate(intervalBinding: \.updateInterval)
///   var updateMetrics: () -> Void
///
///   init() {
///     updateMetrics = { [weak self] in
///       self?.cpuUsage = self?.getCPUUsage() ?? 0.0
///     }
///
///     // Property wrapper automatically observes updateInterval changes
///   }
/// }
/// ```
@propertyWrapper
class PeriodicUpdate<Root: AnyObject> {
  private var timer: Timer?
  private var updateClosure: (() -> Void)?
  private weak var root: Root?
  private let intervalKeyPath: ReferenceWritableKeyPath<Root, Double>
  private var cancellable: AnyCancellable?

  private var currentInterval: TimeInterval {
    guard let root = root else { return 2.0 }
    return root[keyPath: intervalKeyPath]
  }

  private var isRunning: Bool {
    timer != nil
  }

  /// Initialize with a key path to the interval property
  init(intervalBinding: ReferenceWritableKeyPath<Root, Double>) {
    self.intervalKeyPath = intervalBinding
  }

  var wrappedValue: (() -> Void) {
    get { updateClosure ?? {} }
    set { updateClosure = newValue }
  }

  var projectedValue: PeriodicUpdate<Root> {
    self
  }

  /// Bind to the plugin instance and start observing interval changes
  func bind(to instance: Root) where Root: ObservableObject {
    self.root = instance

    // Observe changes to the interval property
    cancellable = instance.objectWillChange.sink { [weak self] _ in
      // When any property changes, check if we need to reconfigure timer
      if let self = self, self.isRunning {
        // Debounce: restart timer after changes settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          if self.isRunning {
            self.restart()
          }
        }
      }
    }
  }

  /// Start periodic execution
  func start() {
    let newTimer = Timer.scheduledTimer(
      withTimeInterval: currentInterval,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateClosure?()
      }
    }
    timer = newTimer
    // Schedule on .common mode to fire during UI tracking
    RunLoop.main.add(newTimer, forMode: .common)

    // Immediate first update
    Task { @MainActor in
      updateClosure?()
    }
  }

  /// Stop periodic execution
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Restart with current interval
  private func restart() {
    stop()
    start()
  }

  deinit {
    stop()
    cancellable?.cancel()
  }
}
```

**Key Design Choice:** Interval is bound via KeyPath, not hardcoded. Framework (plugin setting) controls timing.

---

### 2. Simplified Alternative: Convention-Based Binding

**Even better: Eliminate the KeyPath parameter entirely. Use convention.**

```swift
/// Property wrapper that manages periodic timer execution.
/// Automatically binds to a property named 'updateInterval' on the parent.
///
/// Convention: Plugin MUST have a property named 'updateInterval: Double'
@propertyWrapper
class PeriodicUpdate {
  private var timer: Timer?
  private var updateClosure: (() -> Void)?
  private var intervalProvider: (() -> TimeInterval)?

  init() {}

  var wrappedValue: (() -> Void) {
    get { updateClosure ?? {} }
    set { updateClosure = newValue }
  }

  var projectedValue: PeriodicUpdate {
    self
  }

  /// Bind interval provider (called by macro-generated code)
  func bindInterval(_ provider: @escaping () -> TimeInterval) {
    self.intervalProvider = provider
  }

  private var currentInterval: TimeInterval {
    intervalProvider?() ?? 2.0
  }

  func start() {
    let newTimer = Timer.scheduledTimer(
      withTimeInterval: currentInterval,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateClosure?()
      }
    }
    timer = newTimer
    RunLoop.main.add(newTimer, forMode: .common)

    Task { @MainActor in
      updateClosure?()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Reconfigure timer with new interval
  func reconfigure() {
    guard timer != nil else { return }
    stop()
    start()
  }

  deinit {
    stop()
  }
}
```

---

### 3. @PluginSetting Property Wrapper

**Purpose:** Automatic UserDefaults persistence and UI generation.

```swift
// Sources/Pointless/Plugins/PropertyWrappers/PluginSetting.swift

import Foundation
import Combine

/// Property wrapper that automatically persists plugin settings to UserDefaults
/// and triggers reconfiguration when changed.
@propertyWrapper
class PluginSetting<Value> {
  private let key: String
  private var storage: Value
  private let metadata: SettingMetadata

  let label: String
  let range: ClosedRange<Double>?  // For sliders
  let options: [String]?            // For dropdowns

  /// Callback triggered when value changes (used to reconfigure timers, etc.)
  var onValueChanged: ((Value) -> Void)?

  init(
    wrappedValue: Value,
    key: String,
    label: String,
    range: ClosedRange<Double>? = nil,
    options: [String]? = nil
  ) {
    self.key = key
    self.label = label
    self.range = range
    self.options = options
    self.storage = wrappedValue
    self.metadata = SettingMetadata(key: key, label: label, defaultValue: wrappedValue)
  }

  var wrappedValue: Value {
    get { storage }
    set {
      storage = newValue
      onValueChanged?(newValue)
    }
  }

  var projectedValue: PluginSetting<Value> {
    self
  }

  func loadFromUserDefaults(pluginID: String) {
    let userDefaultsKey = "plugin.\(pluginID).\(key)"
    if let saved = UserDefaults.standard.object(forKey: userDefaultsKey) as? Value {
      storage = saved
    }
  }

  func saveToUserDefaults(pluginID: String) {
    let userDefaultsKey = "plugin.\(pluginID).\(key)"
    UserDefaults.standard.set(storage, forKey: userDefaultsKey)
  }
}

struct SettingMetadata {
  let key: String
  let label: String
  let defaultValue: Any
}
```

---

### 4. @Plugin Macro (Generates Glue Code)

**Purpose:** Auto-generate Plugin protocol conformance and wire up property wrappers.

```swift
// The macro generates this binding code:

extension CPUPlugin: Plugin {
  var id: String { "pointless.cpu" }
  var name: String { "CPU" }

  var settings: PluginSettings {
    // Auto-discovered from @PluginSetting properties
    PluginSettings(definitions: [
      .slider(
        key: "updateInterval",
        label: $updateInterval.label,
        range: $updateInterval.range!,
        defaultValue: 2.0
      )
    ])
  }

  func configure(_ values: [String: Any]) {
    // Auto-generated: Load settings from UserDefaults
    if let updateInterval = values["updateInterval"] as? Double {
      self.updateInterval = updateInterval
    }
  }

  func start() {
    // Bind interval provider to @PeriodicUpdate
    $updateMetrics.bindInterval { [weak self] in
      self?.updateInterval ?? 2.0
    }

    // Start all @PeriodicUpdate properties
    $updateMetrics.start()
  }

  func stop() {
    // Stop all @PeriodicUpdate properties
    $updateMetrics.stop()
  }
}
```

**Critical:** The macro wires `updateInterval` setting to `@PeriodicUpdate` via closure binding.

---

## Implementation Example: CPUPlugin

### Complete Implementation

```swift
@Plugin(id: "pointless.cpu", name: "CPU")
class CPUPlugin: ObservableObject {
  @Published var menuBarText = "CPU --"

  // Framework controls this via settings UI
  @PluginSetting(
    key: "updateInterval",
    label: "Update Interval (seconds)",
    range: 1.0...60.0
  )
  var updateInterval: Double = 2.0

  // Timer automatically uses updateInterval from above
  @PeriodicUpdate
  var updateMetrics: () -> Void

  private var cpuUsage: Double = 0.0

  init() {
    // Define what happens on each framework-driven update
    updateMetrics = { [weak self] in
      guard let self = self else { return }
      self.cpuUsage = self.getCPUUsage()
      self.menuBarText = String(format: "CPU %.0f%%", self.cpuUsage * 100)
      Logger.debug("CPU updated: \(String(format: "%.1f%%", self.cpuUsage * 100))")
    }

    // Wire up updateInterval changes to trigger timer reconfiguration
    $updateInterval.onValueChanged = { [weak self] newInterval in
      self?.$updateMetrics.reconfigure()
    }
  }

  func detailView() -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "cpu")
          Text("CPU")
            .font(.headline)
        }
        Text(String(format: "%.1f%%", cpuUsage * 100))
          .font(.system(.title, design: .monospaced))
        Text("Updates every \(String(format: "%.1f", updateInterval))s")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding()
    )
  }

  // MARK: - CPU Usage

  private func getCPUUsage() -> Double {
    // ... existing implementation ...
    return 0.0
  }
}
```

**Key Insight:**
- `@PluginSetting` declares "this is configurable"
- `@PeriodicUpdate` declares "call me periodically"
- `@Plugin` macro wires them together: setting changes → timer reconfigures
- **No hardcoded intervals in @PeriodicUpdate**

---

## Even Cleaner: Macro Handles All Wiring

The macro can detect the pattern and auto-wire:

```swift
@Plugin(id: "pointless.cpu", name: "CPU")
class CPUPlugin: ObservableObject {
  @Published var menuBarText = "CPU --"

  @PluginSetting(key: "updateInterval", label: "Update Interval", range: 1.0...60.0)
  var updateInterval: Double = 2.0

  @PeriodicUpdate  // Macro auto-binds to updateInterval
  var updateMetrics: () -> Void

  private var cpuUsage: Double = 0.0

  init() {
    updateMetrics = { [weak self] in
      guard let self = self else { return }
      self.cpuUsage = self.getCPUUsage()
      self.menuBarText = String(format: "CPU %.0f%%", self.cpuUsage * 100)
    }

    // Macro generates all wiring code - nothing needed here!
  }

  func detailView() -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "cpu")
          Text("CPU").font(.headline)
        }
        Text(String(format: "%.1f%%", cpuUsage * 100))
          .font(.system(.title, design: .monospaced))
      }
      .padding()
    )
  }

  private func getCPUUsage() -> Double { return 0.0 }
}
```

**Macro-generated `start()` method:**
```swift
func start() {
  // Auto-wire updateInterval → @PeriodicUpdate
  $updateMetrics.bindInterval { [weak self] in
    self?.updateInterval ?? 2.0
  }

  // Auto-wire updateInterval changes → reconfigure timer
  $updateInterval.onValueChanged = { [weak self] _ in
    self?.$updateMetrics.reconfigure()
  }

  // Start timer
  $updateMetrics.start()
}
```

**The framework controls timing. The plugin just reacts.**

---

## Comparison: Who Controls Timing?

### ❌ WRONG (Hardcoded)
```swift
@PeriodicUpdate(interval: 2.0)  // Hardcoded! Framework can't control this
var updateMetrics: () -> Void
```

### ✅ CORRECT (Framework-Controlled)
```swift
@PluginSetting(key: "updateInterval", ...)
var updateInterval: Double = 2.0  // Framework controls this via UI

@PeriodicUpdate  // Automatically bound to updateInterval
var updateMetrics: () -> Void
```

---

## Future Plugins: Zero Configuration

```swift
@Plugin(id: "pointless.memory", name: "Memory")
class MemoryPlugin: ObservableObject {
  @Published var menuBarText = "MEM --"

  @PluginSetting(key: "updateInterval", label: "Update Interval", range: 1.0...60.0)
  var updateInterval: Double = 2.0

  @PeriodicUpdate
  var updateMetrics: () -> Void

  private var memoryUsage: Double = 0.0

  init() {
    updateMetrics = { [weak self] in
      guard let self = self else { return }
      self.memoryUsage = self.getMemoryUsage()
      self.menuBarText = String(format: "MEM %.0f%%", self.memoryUsage * 100)
    }
  }

  func detailView() -> AnyView {
    AnyView(Text("Memory: \(memoryUsage)"))
  }

  private func getMemoryUsage() -> Double { return 0.0 }
}
```

**The pattern is identical. Copy-paste-modify. Framework handles all wiring.**

---

## Implementation Summary

### Property Wrappers
1. **@PeriodicUpdate** - Timer management (no interval parameter!)
2. **@PluginSetting** - Settings persistence + UI generation

### Macro
3. **@Plugin** - Generates:
   - Plugin protocol conformance
   - Binding code: `updateInterval` → `@PeriodicUpdate`
   - Auto-wiring: setting changes → timer reconfigures

### Result
- Plugin declares settings
- Plugin declares periodic work
- Framework wires them together
- **Framework controls all timing**

---

## This IS Correct Metaprogramming

**Separation of concerns:**
- Plugin: Business logic (what to measure, how to display)
- Framework: Cross-cutting concerns (timing, persistence, lifecycle)

**Declarative over imperative:**
- Declare `@PluginSetting` → Framework generates UI + persistence
- Declare `@PeriodicUpdate` → Framework manages timer lifecycle
- Declare `@Plugin` → Framework generates protocol conformance

**Convention over configuration:**
- Standard property name: `updateInterval`
- Standard pattern: `@PluginSetting` + `@PeriodicUpdate`
- Macro auto-discovers and wires them

**Zero boilerplate. Framework controls everything.**
