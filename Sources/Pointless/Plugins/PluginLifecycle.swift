import Combine
import Foundation
import OSLog

/// Manages the timer, settings, and suspend/resume lifecycle for a plugin.
/// Plugins don't touch this directly — they use `setupPeriodicUpdate()` from the
/// default implementations extension, and the lifecycle handles the rest.
class PluginLifecycle {
  var settingDefinitions: [SettingDefinition] = []

  private(set) var timer: Timer?
  private var updateAction: (() -> Void)?
  private(set) var updateInterval: TimeInterval = 2.0

  private enum SuspendState {
    case running
    case suspended(wasActive: Bool)
  }
  private var suspendState: SuspendState = .running

  private var cancellables = Set<AnyCancellable>()

  private var isSuspended: Bool {
    if case .suspended = suspendState { return true }
    return false
  }

  /// Attach a repeating action to this lifecycle, watching `interval` on `plugin` for changes.
  ///
  /// - objectWillChange fires *before* the property updates, so we defer one run-loop turn
  ///   to read the new value.
  func configurePeriodicUpdate<P: Plugin>(
    plugin: P,
    interval: KeyPath<P, TimeInterval>,
    action: @escaping () -> Void
  ) {
    self.updateAction = action
    self.updateInterval = plugin[keyPath: interval]

    plugin.objectWillChange.sink { [weak self, weak plugin] _ in
      DispatchQueue.main.async { [weak self, weak plugin] in
        guard let self, let plugin else { return }
        let newInterval = plugin[keyPath: interval]

        if newInterval != self.updateInterval {
          self.updateInterval = newInterval
          if plugin.isEnabled { self.restart() }
        }

        if plugin.isEnabled && self.timer == nil && !self.isSuspended {
          self.start()
        } else if !plugin.isEnabled && self.timer != nil {
          self.stop()
        }
      }
    }
    .store(in: &cancellables)
  }

  func start() {
    guard let action = updateAction, !isSuspended, timer == nil else { return }

    let timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
      Task { @MainActor in action() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer

    Logger.debug("Timer started with interval \(updateInterval)s", logger: Logger.pluginLifecycle)
    Task { @MainActor in action() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func restart() {
    guard timer != nil else { return }
    stop()
    start()
    Logger.debug("Timer restarted with interval \(updateInterval)s", logger: Logger.pluginLifecycle)
  }

  /// Pause polling while the screen is off or locked.
  func suspend() {
    guard case .running = suspendState else { return }
    suspendState = .suspended(wasActive: timer != nil)
    stop()
    Logger.debug("Timer suspended", logger: Logger.pluginLifecycle)
  }

  /// Resume polling after the screen wakes.
  func resume() {
    guard case .suspended(let wasActive) = suspendState else { return }
    suspendState = .running
    if wasActive { start() }
    Logger.debug("Timer resumed", logger: Logger.pluginLifecycle)
  }

  deinit {
    stop()
    cancellables.removeAll()
  }
}
