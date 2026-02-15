import SwiftUI

/// Auto-generated settings UI from plugin definitions
public struct SettingsView: View {
  public init() {}

  @ObservedObject var pluginRegistry = PluginRegistry.shared
  @ObservedObject var widgetRegistry = WidgetRegistry.shared
  @State private var values: [String: [String: Any]] = [:]
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

  @ViewBuilder
  private func settingView(for definition: SettingDefinition, plugin: AnyPlugin) -> some View {
    switch definition {
    case .slider(let key, let label, let range, let defaultValue, let step):
      VStack(alignment: .leading) {
        Text(label)
          .font(.subheadline)
        HStack {
          Slider(
            value: binding(for: plugin.id, key: key, default: defaultValue),
            in: range,
            step: step
          )
          let currentValue = getValue(for: plugin.id, key: key, default: defaultValue) as? Double ?? defaultValue
          let format = step >= 1.0 ? "%.0f" : "%.1f"
          Text(String(format: format, currentValue))
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 40)
        }
      }

    case .toggle(let key, let label, let defaultValue):
      Toggle(label, isOn: binding(for: plugin.id, key: key, default: defaultValue))

    case .text(let key, let label, let defaultValue):
      VStack(alignment: .leading) {
        Text(label)
          .font(.subheadline)
        TextField("", text: binding(for: plugin.id, key: key, default: defaultValue))
          .textFieldStyle(.roundedBorder)
      }

    case .dropdown(let key, let label, let options, let defaultValue):
      VStack(alignment: .leading) {
        Text(label)
          .font(.subheadline)
        Picker("", selection: binding(for: plugin.id, key: key, default: defaultValue)) {
          ForEach(options, id: \.self) { option in
            Text(option).tag(option)
          }
        }
        .pickerStyle(.menu)
      }

    case .hotkey(let key, let label, let defaultValue):
      VStack(alignment: .leading) {
        Text(label)
          .font(.subheadline)
        TextField("Press shortcut...", text: binding(for: plugin.id, key: key, default: defaultValue))
          .textFieldStyle(.roundedBorder)
      }

    case .color(let key, let label, let defaultValue):
      let colorMode = getValue(for: plugin.id, key: "colorMode", default: "dynamic") as? String ?? "dynamic"
      if colorMode == "custom" {
        VStack(alignment: .leading) {
          Text(label)
            .font(.subheadline)
          ColorPicker(
            "",
            selection: colorBinding(for: plugin.id, key: key, default: defaultValue),
            supportsOpacity: false
          )
        }
      }
    }
  }

  private func colorBinding(for pluginID: String, key: String, default defaultValue: String) -> Binding<Color> {
    Binding(
      get: {
        let hexString = getValue(for: pluginID, key: key, default: defaultValue) as? String ?? defaultValue
        return Color(hex: hexString) ?? Color.blue
      },
      set: { newColor in
        setValue(newColor.toHex(), for: pluginID, key: key)
      }
    )
  }

  // MARK: - Bindings

  private func binding<T>(for pluginID: String, key: String, default defaultValue: T) -> Binding<T> {
    Binding(
      get: { getValue(for: pluginID, key: key, default: defaultValue) as? T ?? defaultValue },
      set: { newValue in
        setValue(newValue, for: pluginID, key: key)
      }
    )
  }

  private func getValue(for pluginID: String, key: String, default defaultValue: Any) -> Any {
    return values[pluginID]?[key] ?? defaultValue
  }

  private func setValue(_ value: Any, for pluginID: String, key: String) {
    if values[pluginID] == nil {
      values[pluginID] = [:]
    }
    values[pluginID]?[key] = value

    saveSettings(for: pluginID)

    if let plugin = pluginRegistry.plugins.first(where: { $0.id == pluginID }) {
      plugin.configure(values[pluginID] ?? [:])
    }
  }

  // MARK: - Persistence

  private func loadSettings() {
    for plugin in pluginRegistry.plugins {
      if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(plugin.id)") {
        values[plugin.id] = saved
      } else {
        var defaults: [String: Any] = [:]
        for definition in plugin.settings().definitions {
          defaults[definition.key] = definition.defaultValue
        }
        values[plugin.id] = defaults
      }
    }
  }

  private func saveSettings(for pluginID: String) {
    if let pluginValues = values[pluginID] {
      UserDefaults.standard.set(pluginValues, forKey: "plugin.\(pluginID)")
    }
  }
}
