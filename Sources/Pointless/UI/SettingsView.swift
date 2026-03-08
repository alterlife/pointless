import SwiftUI

/// Auto-generated settings UI from plugin definitions
public struct SettingsView: View {
  public init() {}

  @ObservedObject var pluginRegistry = PluginRegistry.shared
  @ObservedObject var widgetRegistry = WidgetRegistry.shared
  @State var values: [String: [String: Any]] = [:]
  @State private var selectedTab: String = "pointless.keyboard"
  @State private var draggedMenuBarWidgetId: String?
  @State private var draggedMenuWidgetId: String?

  public var body: some View {
    TabView(selection: $selectedTab) {
      // Pointless tab (keyboard plugin settings — always visible)
      keyboardSettingsTab()
        .tabItem { Label("Pointless", systemImage: "keyboard") }
        .tag("pointless.keyboard")

      // Plugins tab — card layout with per-widget toggles
      pluginsTab()
        .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        .tag("plugins")

      // Conditional per-plugin settings tabs (only when enabled, not keyboard)
      ForEach(enabledNonKeyboardPlugins, id: \.id) { plugin in
        pluginSettingsTab(for: plugin)
          .tabItem { Label(plugin.name, systemImage: plugin.icon) }
          .tag(plugin.id)
      }
    }
    .frame(minWidth: 800, minHeight: 600)
    .onAppear {
      loadSettings()
    }
  }

  private var enabledNonKeyboardPlugins: [AnyPlugin] {
    pluginRegistry.plugins.filter { $0.isEnabled && $0.id != "pointless.keyboard" }
  }

  // MARK: - Pointless Tab (Keyboard Settings)

  @ViewBuilder
  private func keyboardSettingsTab() -> some View {
    if let keyboard = pluginRegistry.plugins.first(where: { $0.id == "pointless.keyboard" }) {
      pluginSettingsTab(for: keyboard)
    } else {
      Text("Keyboard plugin not found")
        .foregroundColor(.secondary)
    }
  }

  // MARK: - Plugins Tab

  @ViewBuilder
  private func pluginsTab() -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // Plugins section
        pluginsSection()

        // Icon Widgets section
        if !widgetRegistry.sortedAllMenuBarWidgets.isEmpty {
          iconWidgetsSection()
        }

        // Menu Widgets section
        if !widgetRegistry.sortedAllMenuWidgets.isEmpty {
          menuWidgetsSection()
        }
      }
      .padding()
    }
  }

  // MARK: - Plugins Section

  @ViewBuilder
  private func pluginsSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Plugins")
        .font(.headline)
        .foregroundColor(.secondary)

      VStack(spacing: 0) {
        ForEach(Array(pluginRegistry.plugins.enumerated()), id: \.element.id) { index, plugin in
          if index > 0 {
            Divider()
          }
          pluginRow(for: plugin)
        }
      }
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
    }
  }

  @ViewBuilder
  private func pluginRow(for plugin: AnyPlugin) -> some View {
    HStack(spacing: 10) {
      Image(systemName: plugin.icon)
        .foregroundColor(plugin.isEnabled ? .accentColor : .secondary)
        .frame(width: 20)

      Text(plugin.name)
        .font(.body)

      Spacer()

      if plugin.isEnabled && pluginHasSettings(plugin) {
        Button("Configure") {
          selectedTab = plugin.id == "pointless.keyboard" ? "pointless.keyboard" : plugin.id
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundColor(.accentColor)
      }

      Toggle("", isOn: pluginEnabledBinding(for: plugin))
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func pluginHasSettings(_ plugin: AnyPlugin) -> Bool {
    plugin.id == "pointless.keyboard" || !plugin.settings().definitions.isEmpty
  }

  // MARK: - Widget List Sections

  @ViewBuilder
  private func iconWidgetsSection() -> some View {
    widgetListSection(
      title: "Menu Bar Widgets",
      widgets: widgetRegistry.sortedAllMenuBarWidgets,
      visibilityBinding: menuBarVisibilityBinding,
      draggedId: $draggedMenuBarWidgetId
    ) { widget in
      MenuBarActiveDropDelegate(
        targetWidgetId: widget.id,
        draggedWidgetId: $draggedMenuBarWidgetId,
        widgetRegistry: widgetRegistry
      )
    }
  }

  @ViewBuilder
  private func menuWidgetsSection() -> some View {
    widgetListSection(
      title: "Menu Widgets",
      widgets: widgetRegistry.sortedAllMenuWidgets,
      visibilityBinding: menuVisibilityBinding,
      draggedId: $draggedMenuWidgetId
    ) { widget in
      MenuActiveDropDelegate(
        targetWidgetId: widget.id,
        draggedWidgetId: $draggedMenuWidgetId,
        widgetRegistry: widgetRegistry
      )
    }
  }

  @ViewBuilder
  private func widgetListSection<W: WidgetProtocol & Identifiable, D: DropDelegate>(
    title: String,
    widgets: [W],
    visibilityBinding: @escaping (String) -> Binding<Bool>,
    draggedId: Binding<String?>,
    dropDelegate: @escaping (W) -> D
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundColor(.secondary)

      VStack(spacing: 0) {
        ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
          if index > 0 {
            Divider()
          }
          widgetRow(
            widget: widget,
            isVisible: visibilityBinding(widget.id),
            isPluginEnabled: pluginEnabled(for: widget.pluginId)
          )
          .onDrag {
            draggedId.wrappedValue = widget.id
            return NSItemProvider(object: widget.id as NSString)
          }
          .onDrop(of: [.text], delegate: dropDelegate(widget))
        }
      }
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
    }
  }

  // MARK: - Widget Row

  @ViewBuilder
  private func widgetRow(
    widget: some WidgetProtocol,
    isVisible: Binding<Bool>,
    isPluginEnabled: Bool
  ) -> some View {
    let pluginIcon = pluginRegistry.plugins.first { $0.id == widget.pluginId }?.icon ?? "puzzlepiece"

    HStack(spacing: 10) {
      Image(systemName: "line.3.horizontal")
        .font(.caption)
        .foregroundColor(.secondary)

      Toggle("", isOn: isVisible)
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(!isPluginEnabled)

      Image(systemName: pluginIcon)
        .font(.caption)
        .foregroundColor(isPluginEnabled ? .secondary : Color(NSColor.quaternaryLabelColor))
        .frame(width: 16)

      Text(widget.name)
        .font(.body)
        .foregroundColor(isPluginEnabled ? .primary : .secondary)

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .opacity(isPluginEnabled ? 1.0 : 0.5)
  }

  private func pluginEnabled(for pluginId: String) -> Bool {
    pluginRegistry.plugins.first { $0.id == pluginId }?.isEnabled ?? false
  }

  // MARK: - Plugin Settings Tab

  @ViewBuilder
  private func pluginSettingsTab(for plugin: AnyPlugin) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("\(plugin.name) Settings")
          .font(.title)
          .fontWeight(.bold)

        Divider()

        if plugin.settings().definitions.isEmpty {
          Text("No settings available")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(plugin.settings().definitions) { definition in
            settingView(for: definition, plugin: plugin)
          }
        }
      }
      .padding()
    }
  }
}
