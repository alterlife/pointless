import Cocoa
import OSLog
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
  public func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      Logger.info("Pointless starting up")

      // Core feature: cursor-free navigation
      KeyboardNavigation.shared.start()
      WidgetRegistry.shared.registerSource(KeyboardNavigation.shared)

      // Optional monitoring plugins (disabled by default, enabled in Settings)
      let plugins: [any Plugin] = [CPUPlugin()]
      PluginRegistry.shared.register(plugins)
      PluginRegistry.shared.loadExternalPlugins()

      Logger.info("Starting \(PluginRegistry.shared.plugins.count) plugin(s)")
      PluginRegistry.shared.plugins.forEach { $0.start() }

      MenuBar.shared.setup()
      ScreenStateMonitor.shared.start()

      Logger.info("Pointless ready")
    }
  }
}
