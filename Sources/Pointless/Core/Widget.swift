import SwiftUI

// MARK: - WidgetSource

/// Anything that provides widgets to the menu bar and menu — plugins and the
/// core navigation feature alike. `WidgetRegistry` observes each source's
/// published state and rebuilds the widget lists when it changes.
@MainActor
protocol WidgetSource: AnyObject {
  /// Unique identifier, e.g. `"pointless.cpu"` or `"pointless.keyboard"`
  var id: String { get }

  /// SF Symbol name for settings UI
  var icon: String { get }

  /// Whether this source currently provides visible widgets
  var isEnabled: Bool { get }

  func menuBarWidgets() -> [MenuBarWidget]
  func menuWidgets() -> [MenuWidget]
}

// MARK: - Widget Protocol

/// Base protocol for all widgets
protocol WidgetProtocol {
  /// Unique identifier for this widget
  var id: String { get }

  /// ID of the source that provides this widget (plugin or navigation)
  var ownerId: String { get }

  /// Display name
  var name: String { get }

  /// Priority for default ordering (lower = higher priority)
  var priority: Int { get }
}

// MARK: - MenuBarWidget

/// Widget displayed in the status bar (top-right area)
struct MenuBarWidget: WidgetProtocol, Identifiable {
  let id: String
  let ownerId: String
  let name: String
  let priority: Int
  let viewBuilder: () -> AnyView

  init(
    id: String,
    ownerId: String,
    name: String,
    priority: Int = 100,
    @ViewBuilder viewBuilder: @escaping () -> some View
  ) {
    self.id = id
    self.ownerId = ownerId
    self.name = name
    self.priority = priority
    self.viewBuilder = { AnyView(viewBuilder()) }
  }
}

// MARK: - MenuWidget

/// Widget displayed in the dropdown menu
struct MenuWidget: WidgetProtocol, Identifiable {
  let id: String
  let ownerId: String
  let name: String
  let priority: Int
  let viewBuilder: () -> AnyView

  init(
    id: String,
    ownerId: String,
    name: String,
    priority: Int = 100,
    @ViewBuilder viewBuilder: @escaping () -> some View
  ) {
    self.id = id
    self.ownerId = ownerId
    self.name = name
    self.priority = priority
    self.viewBuilder = { AnyView(viewBuilder()) }
  }
}
