import Cocoa
import OSLog
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
  public func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      Logger.info("Pointless starting up")

      // Register built-in plugins
      let plugins: [any Plugin] = [
        KeyboardPlugin(),
        CPUPlugin()
      ]

      for plugin in plugins {
        PluginRegistry.shared.register(plugin)
      }

      PluginRegistry.shared.loadExternalPlugins()

      Logger.info("Starting \(PluginRegistry.shared.plugins.count) plugin(s)")

      for plugin in PluginRegistry.shared.plugins {
        plugin.start()
      }

      // Register widgets from all plugins
      Logger.info("Registering widgets")
      for plugin in PluginRegistry.shared.plugins {
        WidgetRegistry.shared.registerMenuBarWidgets(plugin.menuBarWidgets())
        WidgetRegistry.shared.registerMenuWidgets(plugin.menuWidgets())
      }

      MenuBar.shared.setup()
      ScreenStateMonitor.shared.start()

      Logger.info("Pointless ready")
    }
  }
}
