import SwiftUI

/// Helper extensions for SettingsView widget filtering
extension SettingsView {
  internal func getInactiveMenuBarWidgets() -> [MenuBarWidget] {
    getAllMenuBarWidgets().filter { !widgetRegistry.isMenuBarWidgetVisible($0.id) }
  }

  internal func getInactiveMenuWidgets() -> [MenuWidget] {
    getAllMenuWidgets().filter { !widgetRegistry.isMenuWidgetVisible($0.id) }
  }

  internal func getAllMenuBarWidgets() -> [MenuBarWidget] {
    pluginRegistry.plugins.flatMap { $0.menuBarWidgets() }
  }

  internal func getAllMenuWidgets() -> [MenuWidget] {
    pluginRegistry.plugins.flatMap { $0.menuWidgets() }
  }
}
