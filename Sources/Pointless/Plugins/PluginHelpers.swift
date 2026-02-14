import Combine
import Foundation
import OSLog

// MARK: - Plugin State Storage

/// Internal storage for plugin runtime state
private var pluginState: [ObjectIdentifier: PluginState] = [:]

/// Runtime state for a plugin instance
class PluginState {
  var settingDefinitions: [SettingDefinition] = []
  var timer: Timer?
  var timerAction: (() -> Void)?
  var timerInterval: TimeInterval = 2.0
  var cancellables: Set<AnyCancellable> = []
}

// MARK: - Plugin Extension Helpers

extension Plugin {
  /// Access internal state for this plugin instance
  fileprivate var state: PluginState {
    let key = ObjectIdentifier(self)
    if pluginState[key] == nil {
      pluginState[key] = PluginState()
    }
    guard let state = pluginState[key] else {
      fatalError("Failed to create plugin state for \(id)")
    }
    return state
  }

  // MARK: Helper Methods (called by plugins in initialize())

  /// Declare settings for this plugin
  /// - Parameter definitions: Array of setting definitions
  ///
  /// Example:
  /// ```
  /// settings([
  ///   .slider("updateInterval", label: "Update Interval", range: 1.0...60.0, default: 2.0)
  /// ])
  /// ```
  func settings(_ definitions: [SettingDefinition]) {
    state.settingDefinitions = definitions

    for def in definitions {
      if let saved = UserDefaults.standard.object(forKey: "plugin.\(id).\(def.key)") {
        configure([def.key: saved])
      }
    }
  }

  /// Setup periodic timer with dynamic interval
  /// - Parameters:
  ///   - interval: KeyPath to the interval property
  ///   - action: Closure to execute on each timer tick
  ///
  /// Example:
  /// ```
  /// periodicUpdate(interval: \.updateInterval) { [weak self] in
  ///   self?.update()
  /// }
  /// ```
  func periodicUpdate(interval: KeyPath<Self, TimeInterval>, action: @escaping () -> Void) {
    state.timerAction = action
    state.timerInterval = self[keyPath: interval]

    // When any @Published property changes, check if interval changed and restart timer if needed
    objectWillChange.sink { [weak self] _ in
      guard let self = self else { return }
      let newInterval = self[keyPath: interval]
      if newInterval != self.state.timerInterval {
        self.state.timerInterval = newInterval
        Logger.debug(
          "Timer interval changed to \(newInterval)s for \(self.id)",
          logger: Logger.pluginLifecycle
        )
        if self.state.timer != nil {
          self.recreateTimer()
        }
      }
    }
    .store(in: &state.cancellables)
  }

  /// Recreate timer with current interval
  private func recreateTimer() {
    state.timer?.invalidate()
    state.timer = nil

    guard let action = state.timerAction else { return }

    let timer = Timer.scheduledTimer(
      withTimeInterval: state.timerInterval,
      repeats: true
    ) { _ in
      Task { @MainActor in
        action()
      }
    }

    RunLoop.main.add(timer, forMode: .common)
    state.timer = timer

    Logger.debug(
      "Timer recreated with interval \(self.state.timerInterval)s for \(self.id)",
      logger: Logger.pluginLifecycle
    )
  }

  // MARK: Default Protocol Implementations

  /// Default settings - returns configured definitions
  func settings() -> PluginSettings {
    PluginSettings(definitions: state.settingDefinitions)
  }

  /// Default configure - updates properties via reflection and saves to UserDefaults
  func configure(_ values: [String: Any]) {
    for (key, value) in values {
      UserDefaults.standard.set(value, forKey: "plugin.\(id).\(key)")

      // Use reflection to find and update matching properties via KVC
      let mirror = Mirror(reflecting: self)
      for child in mirror.children {
        if let propertyName = child.label, propertyName == key {
          if let writable = self as? AnyObject {
            writable.setValue(value, forKey: key)
          }
        }
      }
    }
  }

  /// Default start - starts the periodic timer if configured
  func start() {
    guard let action = state.timerAction else {
      Logger.debug("No timer action configured for \(self.id)", logger: Logger.pluginLifecycle)
      return
    }

    let timer = Timer.scheduledTimer(
      withTimeInterval: state.timerInterval,
      repeats: true
    ) { _ in
      Task { @MainActor in
        action()
      }
    }

    RunLoop.main.add(timer, forMode: .common)
    state.timer = timer

    Logger.info("Started plugin \(self.id) (interval: \(self.state.timerInterval)s)")

    Task { @MainActor in
      action()
    }
  }

  /// Default stop - stops the periodic timer
  func stop() {
    state.timer?.invalidate()
    state.timer = nil
    state.cancellables.removeAll()

    Logger.info("Stopped plugin \(self.id)")
  }
}
