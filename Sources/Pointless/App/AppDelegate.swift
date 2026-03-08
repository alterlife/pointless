import Cocoa
import OSLog
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
  public func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      Logger.info("Pointless starting up")

      let plugins: [any Plugin] = [KeyboardPlugin(), CPUPlugin()]
      PluginRegistry.shared.register(plugins)
      PluginRegistry.shared.loadExternalPlugins()

      Logger.info("Starting \(PluginRegistry.shared.plugins.count) plugin(s)")
      PluginRegistry.shared.plugins.forEach { $0.start() }

      Logger.info("Registering widgets")
      PluginRegistry.shared.plugins.forEach { plugin in
        WidgetRegistry.shared.registerMenuBarWidgets(plugin.menuBarWidgets())
        WidgetRegistry.shared.registerMenuWidgets(plugin.menuWidgets())
      }

      MenuBar.shared.setup()
      ScreenStateMonitor.shared.start()

      Logger.info("Pointless ready")
    }
  }
}
