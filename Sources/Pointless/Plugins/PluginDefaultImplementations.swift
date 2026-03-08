import Combine
import Foundation
import OSLog

// MARK: - Lifecycle Storage

private var lifecycleKey: UInt8 = 0

// MARK: - Plugin Default Implementations

/// Default behaviour for class-based plugins via associated objects.
/// Plugins that need custom behaviour override only what differs.
extension Plugin where Self: AnyObject {
  /// The plugin's shared lifecycle — created once on first access, retained for the plugin's lifetime.
  var lifecycle: PluginLifecycle {
    if let existing = objc_getAssociatedObject(self, &lifecycleKey) as? PluginLifecycle {
      return existing
    }
    let lifecycle = PluginLifecycle()
    objc_setAssociatedObject(self, &lifecycleKey, lifecycle, .OBJC_ASSOCIATION_RETAIN)
    return lifecycle
  }

  // MARK: - Setup Helpers

  /// Declare the settings this plugin exposes in the Settings UI.
  func declareSettings(_ definitions: [SettingDefinition]) {
    lifecycle.settingDefinitions = definitions
  }

  /// Register a recurring action whose cadence tracks `interval` on this plugin.
  /// The action fires immediately on start, then repeatedly at the current interval.
  func setupPeriodicUpdate(
    interval: KeyPath<Self, TimeInterval>,
    action: @escaping () -> Void
  ) {
    lifecycle.configurePeriodicUpdate(plugin: self, interval: interval, action: action)
  }

  // MARK: - Protocol Defaults

  func settings() -> PluginSettings {
    PluginSettings(definitions: lifecycle.settingDefinitions)
  }

  /// Merge `values` into the plugin's persisted UserDefaults dictionary.
  /// Plugins that override `configure(with:)` should call this to persist their changes.
  func saveSettings(_ values: [String: Any]) {
    var stored = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") ?? [:]
    values.forEach { stored[$0.key] = $0.value }
    UserDefaults.standard.set(stored, forKey: "plugin.\(id)")
  }

  /// Default: only persist — plugins override this to also apply values to their `@Published` properties.
  func configure(with values: [String: Any]) {
    saveSettings(values)
  }

  func start() {
    if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") {
      configure(with: saved)
    }

    guard isEnabled else {
      Logger.debug("Plugin \(id) is disabled, skipping start", logger: Logger.pluginLifecycle)
      return
    }

    lifecycle.start()
    Logger.info("Started plugin \(id)")
  }

  func stop() {
    lifecycle.stop()
    Logger.info("Stopped plugin \(id)")
  }

  func suspend() { lifecycle.suspend() }
  func resume() { lifecycle.resume() }
}
