import SwiftUI

/// Wrapper that creates @ObservedObject binding for reactive widget updates.
/// Observes the specific owner of the widget — the core navigation feature or
/// a plugin — so the widget re-renders when its data changes.
struct ObservableWidgetView: View {
  @ObservedObject var pluginRegistry = PluginRegistry.shared
  let widgetId: String
  let ownerId: String
  let content: () -> AnyView

  var body: some View {
    if ownerId == KeyboardNavigation.shared.id {
      ObservableNavigationView(content: content)
    } else if let plugin = pluginRegistry.plugins.first(where: { $0.id == ownerId }) {
      // Use ObservablePluginView to create proper @ObservedObject binding to the plugin
      ObservablePluginView(plugin: plugin) { _ in
        content()
      }
    } else {
      // Fallback if owner not found (shouldn't happen in normal operation)
      content()
    }
  }
}

/// Creates the @ObservedObject binding for navigation-owned widgets.
private struct ObservableNavigationView: View {
  @ObservedObject var navigation = KeyboardNavigation.shared
  let content: () -> AnyView

  var body: some View {
    content()
  }
}
