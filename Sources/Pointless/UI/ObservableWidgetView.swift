import SwiftUI

/// Wrapper that creates @ObservedObject binding for reactive widget updates
struct ObservableWidgetView: View {
  @ObservedObject var pluginRegistry = PluginRegistry.shared
  let widgetId: String
  let pluginId: String
  let content: () -> AnyView

  var body: some View {
    // Re-render when any plugin changes (triggers fresh widget creation)
    Group {
      content()
    }
    .id(pluginRegistry.plugins.count) // Force re-render on plugin changes
  }
}
