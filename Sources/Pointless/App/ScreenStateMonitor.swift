import Cocoa
import OSLog

/// Listens for screen sleep/wake events and pauses or resumes all plugins accordingly.
@MainActor
final class ScreenStateMonitor {
  static let shared = ScreenStateMonitor()

  private var observers: [NSObjectProtocol] = []

  private init() {}

  deinit {
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  func stop() {
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observers.removeAll()
  }

  func start() {
    stop()
    observe(NSWorkspace.screensDidSleepNotification) {
      Logger.info("Screen slept — suspending")
      KeyboardNavigation.shared.suspend()
      PluginRegistry.shared.suspendAll()
    }
    observe(NSWorkspace.screensDidWakeNotification) {
      Logger.info("Screen woke — resuming")
      KeyboardNavigation.shared.resume()
      PluginRegistry.shared.resumeAll()
    }
  }

  private func observe(_ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
    let token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { handler() }
    }
    observers.append(token)
  }
}
