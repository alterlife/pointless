import Combine
import Foundation
import OSLog

/// Manages the lifecycle and runtime state for a plugin
class PluginLifecycle {
  // Settings
  var settingDefinitions: [SettingDefinition] = []

  // Timer management
  private(set) var timer: Timer?
  private var updateAction: (() -> Void)?
  private(set) var updateInterval: TimeInterval = 2.0

  // Subscriptions
  private var cancellables = Set<AnyCancellable>()

  /// Configure periodic updates with dynamic interval tracking
  func configurePeriodicUpdate<P: Plugin>(
    plugin: P,
    interval: KeyPath<P, TimeInterval>,
    action: @escaping () -> Void
  ) {
    self.updateAction = action
    self.updateInterval = plugin[keyPath: interval]

    // Watch for changes to update interval or enabled state
    plugin.objectWillChange.sink { [weak self, weak plugin] _ in
      guard let self = self, let plugin = plugin else { return }
      let newInterval = plugin[keyPath: interval]

      if newInterval != self.updateInterval {
        self.updateInterval = newInterval
        if plugin.isEnabled {
          self.restart()
        }
      }

      if plugin.isEnabled && self.timer == nil {
        self.start()
      } else if !plugin.isEnabled && self.timer != nil {
        self.stop()
      }
    }
    .store(in: &cancellables)
  }

  /// Start the timer
  func start() {
    guard let action = updateAction else { return }

    let timer = Timer.scheduledTimer(
      withTimeInterval: updateInterval,
      repeats: true
    ) { _ in
      Task { @MainActor in action() }
    }

    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer

    Logger.debug("Timer started with interval \(updateInterval)s", logger: Logger.pluginLifecycle)

    // Run immediately
    Task { @MainActor in action() }
  }

  /// Stop the timer
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Restart the timer with new interval
  func restart() {
    guard timer != nil else { return }
    stop()
    start()
    Logger.debug("Timer restarted with interval \(updateInterval)s", logger: Logger.pluginLifecycle)
  }

  /// Cleanup on deinitialization
  deinit {
    stop()
    cancellables.removeAll()
  }
}
