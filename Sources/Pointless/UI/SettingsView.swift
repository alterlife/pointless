import SwiftUI

/// Auto-generated settings UI from plugin definitions
public struct SettingsView: View {
  public init() {}

  @ObservedObject var pluginRegistry = PluginRegistry.shared
  @ObservedObject var widgetRegistry = WidgetRegistry.shared
  @State var values: [String: [String: Any]] = [:]
  @State private var selectedTab: String = "menubar"
  @State private var draggedMenuBarWidgetId: String?
  @State private var draggedMenuWidgetId: String?

  public var body: some View {
    TabView(selection: $selectedTab) {
      menuBarTab()
        .tabItem {
          Label("Menu Bar", systemImage: "macwindow")
        }
        .tag("menubar")

      menuDetailTab()
        .tabItem {
          Label("Menu Detail", systemImage: "list.bullet")
        }
        .tag("menudetail")

      ForEach(pluginRegistry.plugins, id: \.id) { plugin in
        pluginSettingsTab(for: plugin)
          .tabItem {
            Label(plugin.name, systemImage: "puzzlepiece")
          }
          .tag(plugin.id)
      }
    }
    .frame(minWidth: 800, minHeight: 600)
    .onAppear {
      loadSettings()
    }
  }

  // MARK: - Menu Bar Tab

  @ViewBuilder
  private func menuBarTab() -> some View {
    HStack(spacing: 0) {
      menuBarActiveSection()
      Divider()
      menuBarLibrarySection()
    }
  }

  @ViewBuilder
  private func menuBarActiveSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Active Widgets")
        .font(.headline)
        .padding(.horizontal)
        .padding(.top)

      Text("Drag to reorder • Drag to library to remove")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      // WYSIWYG Preview
      HStack(spacing: 0) {
        ForEach(Array(widgetRegistry.orderedMenuBarWidgets.enumerated()), id: \.element.id) { index, widget in
          HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
              .font(.caption2)
              .foregroundColor(.secondary)

            if index > 0 {
              Text(" | ")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            }

            ObservableWidgetView(widgetId: widget.id, pluginId: widget.pluginId) {
              widget.viewBuilder()
            }
          }
          .padding(4)
          .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
          .cornerRadius(4)
          .onDrag {
            draggedMenuBarWidgetId = widget.id
            return NSItemProvider(object: widget.id as NSString)
          }
          .onDrop(of: [.text], delegate: MenuBarActiveDropDelegate(
            targetWidgetId: widget.id,
            draggedWidgetId: $draggedMenuBarWidgetId,
            widgetRegistry: widgetRegistry
          ))
        }

        Spacer()
      }
      .padding()
      .frame(maxWidth: .infinity, minHeight: 200)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
      .padding(.horizontal)

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func menuBarLibrarySection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Library")
        .font(.headline)
        .padding(.horizontal)
        .padding(.top)

      Text("Drag widgets to add them")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      VStack(spacing: 8) {
        ForEach(getInactiveMenuBarWidgets(), id: \.id) { widget in
          HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
              .font(.caption2)
              .foregroundColor(.secondary)

            ObservableWidgetView(widgetId: widget.id, pluginId: widget.pluginId) {
              widget.viewBuilder()
            }
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(NSColor.controlBackgroundColor))
          .cornerRadius(6)
          .opacity(0.7)
          .onDrag {
            draggedMenuBarWidgetId = widget.id
            widgetRegistry.setMenuBarVisibility(widgetId: widget.id, isVisible: true)
            return NSItemProvider(object: widget.id as NSString)
          }
        }

        if getInactiveMenuBarWidgets().isEmpty {
          Text("All widgets active")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
      .cornerRadius(8)
      .padding(.horizontal)
      .onDrop(of: [.text], delegate: MenuBarRemoveDropDelegate(
        draggedWidgetId: $draggedMenuBarWidgetId,
        widgetRegistry: widgetRegistry
      ))

      Spacer()
    }
    .frame(width: 250)
  }

  // MARK: - Menu Detail Tab

  @ViewBuilder
  private func menuDetailTab() -> some View {
    HStack(spacing: 0) {
      menuDetailActiveSection()
      Divider()
      menuDetailLibrarySection()
    }
  }

  @ViewBuilder
  private func menuDetailActiveSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Active Widgets")
        .font(.headline)
        .padding(.horizontal)
        .padding(.top)

      Text("Drag to reorder • Drag to library to remove")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      // WYSIWYG Preview
      ScrollView {
        VStack(spacing: 0) {
          ForEach(widgetRegistry.orderedMenuWidgets, id: \.id) { widget in
            VStack(spacing: 0) {
              HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                  .font(.caption2)
                  .foregroundColor(.secondary)

                ObservableWidgetView(widgetId: widget.id, pluginId: widget.pluginId) {
                  AnyView(widget.viewBuilder().frame(width: 320))
                }
              }
              .padding(.vertical, 8)

              if widget.id != widgetRegistry.orderedMenuWidgets.last?.id {
                Divider()
              }
            }
            .onDrag {
              draggedMenuWidgetId = widget.id
              return NSItemProvider(object: widget.id as NSString)
            }
            .onDrop(of: [.text], delegate: MenuActiveDropDelegate(
              targetWidgetId: widget.id,
              draggedWidgetId: $draggedMenuWidgetId,
              widgetRegistry: widgetRegistry
            ))
          }
        }
      }
      .frame(maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
      .padding(.horizontal)

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func menuDetailLibrarySection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Library")
        .font(.headline)
        .padding(.horizontal)
        .padding(.top)

      Text("Drag widgets to add them")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      VStack(spacing: 8) {
        ForEach(getInactiveMenuWidgets(), id: \.id) { widget in
          HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
              .font(.caption2)
              .foregroundColor(.secondary)

            ObservableWidgetView(widgetId: widget.id, pluginId: widget.pluginId) {
              AnyView(widget.viewBuilder())
            }
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(NSColor.controlBackgroundColor))
          .cornerRadius(6)
          .opacity(0.7)
          .onDrag {
            draggedMenuWidgetId = widget.id
            widgetRegistry.setMenuVisibility(widgetId: widget.id, isVisible: true)
            return NSItemProvider(object: widget.id as NSString)
          }
        }

        if getInactiveMenuWidgets().isEmpty {
          Text("All widgets active")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
      .cornerRadius(8)
      .padding(.horizontal)
      .onDrop(of: [.text], delegate: MenuRemoveDropDelegate(
        draggedWidgetId: $draggedMenuWidgetId,
        widgetRegistry: widgetRegistry
      ))

      Spacer()
    }
    .frame(width: 250)
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
