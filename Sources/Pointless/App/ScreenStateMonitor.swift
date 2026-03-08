import Cocoa
import OSLog

/// Listens for screen sleep/wake events and pauses or resumes all plugins accordingly.
@MainActor
class ScreenStateMonitor {
  static let shared = ScreenStateMonitor()

  private init() {}

  func start() {
    observe(NSWorkspace.screensDidSleepNotification) {
      Logger.info("Screen slept — suspending plugins")
      PluginRegistry.shared.suspendAll()
    }
    observe(NSWorkspace.screensDidWakeNotification) {
      Logger.info("Screen woke — resuming plugins")
      PluginRegistry.shared.resumeAll()
    }
  }

  private func observe(_ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in handler() }
    }
  }
}
