import Combine
import Foundation
import OSLog

// MARK: - Plugin Runtime State

private var runtimeState: [ObjectIdentifier: RuntimeState] = [:]

class RuntimeState {
  var definitions: [SettingDefinition] = []
  var timer: Timer?
  var updateAction: (() -> Void)?
  var updateInterval: TimeInterval = 2.0
  var subscriptions: Set<AnyCancellable> = []
}

// MARK: - Plugin Extension Helpers

extension Plugin {
  fileprivate var runtime: RuntimeState {
    let key = ObjectIdentifier(self)

    if let existing = runtimeState[key] {
      return existing
    }

    let newState = RuntimeState()
    runtimeState[key] = newState
    return newState
  }

  // MARK: Helper Methods

  /// Declare settings for this plugin
  ///
  /// Example:
  /// ```
  /// declareSettings([
  ///   .slider(key: "updateInterval", label: "Update Interval",
  ///           range: 1.0...60.0, defaultValue: 2.0)
  /// ])
  /// ```
  func declareSettings(_ definitions: [SettingDefinition]) {
    runtime.definitions = definitions
  }

  /// Setup periodic updates with dynamic interval
  ///
  /// The timer automatically reconfigures when the interval property changes.
  ///
  /// Example:
  /// ```
  /// setupPeriodicUpdate(interval: \.updateInterval) { [weak self] in
  ///   self?.refresh()
  /// }
  /// ```
  func setupPeriodicUpdate(
    interval: KeyPath<Self, TimeInterval>,
    action: @escaping () -> Void
  ) {
    runtime.updateAction = action
    runtime.updateInterval = self[keyPath: interval]

    objectWillChange.sink { [weak self] _ in
      guard let self = self else { return }
      let currentInterval = self[keyPath: interval]

      if currentInterval != self.runtime.updateInterval {
        self.runtime.updateInterval = currentInterval
        if self.isEnabled {
          self.restartTimer()
        }
      }

      if self.isEnabled && self.runtime.timer == nil {
        self.startTimer()
      } else if !self.isEnabled && self.runtime.timer != nil {
        self.stopTimer()
      }
    }
    .store(in: &runtime.subscriptions)
  }

  private func restartTimer() {
    guard runtime.timer != nil else { return }

    stopTimer()
    startTimer()

    Logger.debug(
      "Timer restarted with interval \(runtime.updateInterval)s",
      logger: Logger.pluginLifecycle
    )
  }

  private func startTimer() {
    guard let action = runtime.updateAction else { return }

    let timer = Timer.scheduledTimer(
      withTimeInterval: runtime.updateInterval,
      repeats: true
    ) { _ in
      Task { @MainActor in action() }
    }

    RunLoop.main.add(timer, forMode: .common)
    runtime.timer = timer
  }

  private func stopTimer() {
    runtime.timer?.invalidate()
    runtime.timer = nil
  }

  // MARK: Default Protocol Implementations

  func settings() -> PluginSettings {
    PluginSettings(definitions: runtime.definitions)
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
    if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") {
      configure(saved)
    }

    guard isEnabled else {
      Logger.debug("Plugin \(id) is disabled, skipping start", logger: Logger.pluginLifecycle)
      return
    }

    guard runtime.updateAction != nil else {
      Logger.debug("No update action configured", logger: Logger.pluginLifecycle)
      return
    }

    startTimer()
    Logger.info("Started plugin \(id) (interval: \(runtime.updateInterval)s)")

    Task { @MainActor in
      runtime.updateAction?()
    }
  }

  func stop() {
    stopTimer()
    runtime.subscriptions.removeAll()

    let key = ObjectIdentifier(self)
    runtimeState.removeValue(forKey: key)

    Logger.info("Stopped plugin \(id)")
  }
}
