import Foundation

// MARK: - Widget Type

/// Type of widget for configuration purposes
enum WidgetType: String, Codable {
  case menuBar
  case menu
}

// MARK: - Widget Configuration

/// Persisted configuration for a widget
struct WidgetConfig: Codable, Identifiable {
  let id: String
  let widgetType: WidgetType
  var isVisible: Bool
  var position: Int

  init(id: String, widgetType: WidgetType, isVisible: Bool = true, position: Int = 0) {
    self.id = id
    self.widgetType = widgetType
    self.isVisible = isVisible
    self.position = position
  }
}
