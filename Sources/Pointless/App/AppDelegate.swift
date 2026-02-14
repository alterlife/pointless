import Cocoa
import OSLog
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
  public func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      Logger.info("Pointless starting up")

      // Register built-in plugins
      let plugins: [any Plugin] = [
        CPUPlugin()
        // Add more built-in plugins here
      ]

      for plugin in plugins {
        PluginRegistry.shared.register(plugin)
      }

      PluginRegistry.shared.loadExternalPlugins()

      Logger.info("Starting \(PluginRegistry.shared.plugins.count) plugin(s)")

      for plugin in PluginRegistry.shared.plugins {
        let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(plugin.id)") ?? [:]
        plugin.configure(saved)
      }

      for plugin in PluginRegistry.shared.plugins {
        plugin.start()
      }

      MenuBar.shared.setup()

      Logger.info("Pointless ready")
    }
  }
}
