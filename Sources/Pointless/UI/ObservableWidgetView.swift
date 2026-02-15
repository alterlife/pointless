import SwiftUI

/// Wrapper that creates @ObservedObject binding for reactive widget updates
/// Observes the specific plugin that owns the widget for efficient updates
struct ObservableWidgetView: View {
  @ObservedObject var pluginRegistry = PluginRegistry.shared
  let widgetId: String
  let pluginId: String
  let content: () -> AnyView

  var body: some View {
    // Find and observe the specific plugin that owns this widget
    if let plugin = pluginRegistry.plugins.first(where: { $0.id == pluginId }) {
      // Use ObservablePluginView to create proper @ObservedObject binding to the plugin
      ObservablePluginView(plugin: plugin) { _ in
        content()
      }
    } else {
      // Fallback if plugin not found (shouldn't happen in normal operation)
      content()
    }
  }
}
