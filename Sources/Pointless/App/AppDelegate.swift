import Cocoa
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
  public func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      // Register built-in plugins
      let plugins: [any Plugin] = [
        CPUPlugin()
        // Add more built-in plugins here
      ]

      for plugin in plugins {
        PluginRegistry.shared.register(plugin)
      }

      // Load external plugins from bundles
      PluginRegistry.shared.loadExternalPlugins()

      // Load saved settings and configure plugins
      for plugin in PluginRegistry.shared.plugins {
        let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(plugin.id)") ?? [:]
        plugin.configure(saved)
      }

      // Start all plugins
      for plugin in PluginRegistry.shared.plugins {
        plugin.start()
      }

      // Setup menu bar UI
      MenuBar.shared.setup()
    }
  }
}
