import Combine
import Foundation
import OSLog

// MARK: - Associated Object Key

private var lifecycleKey: UInt8 = 0

// MARK: - Plugin Default Implementations

extension Plugin where Self: AnyObject {
  /// Automatic lifecycle management using associated objects
  /// No boilerplate needed - lifecycle is created on first access
  var lifecycle: PluginLifecycle {
    if let existing = objc_getAssociatedObject(self, &lifecycleKey) as? PluginLifecycle {
      return existing
    }

    let newLifecycle = PluginLifecycle()
    objc_setAssociatedObject(self, &lifecycleKey, newLifecycle, .OBJC_ASSOCIATION_RETAIN)
    return newLifecycle
  }

  // MARK: Helper Methods

  /// Declare settings for this plugin
  func declareSettings(_ definitions: [SettingDefinition]) {
    lifecycle.settingDefinitions = definitions
  }

  /// Setup periodic updates with dynamic interval
  func setupPeriodicUpdate(
    interval: KeyPath<Self, TimeInterval>,
    action: @escaping () -> Void
  ) {
    lifecycle.configurePeriodicUpdate(
      plugin: self,
      interval: interval,
      action: action
    )
  }

  // MARK: Protocol Default Implementations

  func settings() -> PluginSettings {
    PluginSettings(definitions: lifecycle.settingDefinitions)
  }

  func saveSettings(_ values: [String: Any]) {
    let defaults = UserDefaults.standard
    var currentSettings = defaults.dictionary(forKey: "plugin.\(id)") ?? [:]

    for (key, value) in values {
      currentSettings[key] = value
    }

    defaults.set(currentSettings, forKey: "plugin.\(id)")
  }

  func configure(_ values: [String: Any]) {
    saveSettings(values)
  }

  func start() {
    // Load saved settings
    if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") {
      configure(saved)
    }

    guard isEnabled else {
      Logger.debug("Plugin \(id) is disabled, skipping start", logger: Logger.pluginLifecycle)
      return
    }

    // Start lifecycle
    lifecycle.start()

    Logger.info("Started plugin \(id)")
  }

  func stop() {
    lifecycle.stop()
    Logger.info("Stopped plugin \(id)")
  }

  func suspend() {
    lifecycle.suspend()
  }

  func resume() {
    lifecycle.resume()
  }
}
