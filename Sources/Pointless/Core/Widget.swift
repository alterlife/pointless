import SwiftUI

// MARK: - Widget Protocol

/// Base protocol for all widgets
protocol WidgetProtocol {
  /// Unique identifier for this widget
  var id: String { get }

  /// ID of the plugin that provides this widget
  var pluginId: String { get }

  /// Display name
  var name: String { get }

  /// Priority for default ordering (lower = higher priority)
  var priority: Int { get }
}

// MARK: - MenuBarWidget

/// Widget displayed in the status bar (top-right area)
struct MenuBarWidget: WidgetProtocol, Identifiable {
  let id: String
  let pluginId: String
  let name: String
  let priority: Int
  let viewBuilder: () -> AnyView

  init(
    id: String,
    pluginId: String,
    name: String,
    priority: Int = 100,
    @ViewBuilder viewBuilder: @escaping () -> some View
  ) {
    self.id = id
    self.pluginId = pluginId
    self.name = name
    self.priority = priority
    self.viewBuilder = { AnyView(viewBuilder()) }
  }
}

// MARK: - MenuWidget

/// Widget displayed in the dropdown menu
struct MenuWidget: WidgetProtocol, Identifiable {
  let id: String
  let pluginId: String
  let name: String
  let priority: Int
  let viewBuilder: () -> AnyView

  init(
    id: String,
    pluginId: String,
    name: String,
    priority: Int = 100,
    @ViewBuilder viewBuilder: @escaping () -> some View
  ) {
    self.id = id
    self.pluginId = pluginId
    self.name = name
    self.priority = priority
    self.viewBuilder = { AnyView(viewBuilder()) }
  }
}
