import Cocoa
import OSLog

/// Monitors screen sleep/wake events and suspends or resumes all plugins accordingly
@MainActor
class ScreenStateMonitor {
  static let shared = ScreenStateMonitor()

  private init() {}

  func start() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidSleepNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        Logger.info("Screen slept — suspending plugins")
        PluginRegistry.shared.suspendAll()
      }
    }

    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidWakeNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        Logger.info("Screen woke — resuming plugins")
        PluginRegistry.shared.resumeAll()
      }
    }
  }
}
