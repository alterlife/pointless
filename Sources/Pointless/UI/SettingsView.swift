import SwiftUI

/// Auto-generated settings UI from plugin definitions
public struct SettingsView: View {
  public init() {}

  @ObservedObject var registry = PluginRegistry.shared
  @State private var values: [String: [String: Any]] = [:]
  @State private var selectedTab: String = "general"

  public var body: some View {
    TabView(selection: $selectedTab) {
      generalSettingsTab()
        .tabItem {
          Label("General", systemImage: "gearshape")
        }
        .tag("general")

      ForEach(registry.plugins, id: \.id) { plugin in
        pluginSettingsTab(for: plugin)
          .tabItem {
            Label(plugin.name, systemImage: "puzzlepiece")
          }
          .tag(plugin.id)
      }
    }
    .frame(minWidth: 600, minHeight: 500)
    .onAppear {
      loadSettings()
    }
  }

  @ViewBuilder
  private func generalSettingsTab() -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("General Settings")
          .font(.title)
          .fontWeight(.bold)
          .padding(.bottom, 8)

        Text("Framework version: 1.0.0")
          .font(.caption)
          .foregroundColor(.secondary)

        Divider()

        Text("About Pointless")
          .font(.headline)

        Text("A minimal, plugin-driven macOS menu bar app. Add any functionality you want through plugins.")
          .font(.body)
          .foregroundColor(.secondary)
      }
      .padding()
    }
  }

  @ViewBuilder
  private func pluginSettingsTab(for plugin: AnyPlugin) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        previewBox(for: plugin)
          .frame(maxWidth: .infinity, alignment: .trailing)

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
  private func previewBox(for plugin: AnyPlugin) -> some View {
    VStack {
      Text("Preview")
        .font(.caption)
        .foregroundColor(.secondary)

      ObservablePluginView(plugin: plugin) { observedPlugin in
        observedPlugin.detailView()
      }
      .frame(width: 360)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color(NSColor.separatorColor), lineWidth: 1)
      )
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

    if let plugin = registry.plugins.first(where: { $0.id == pluginID }) {
      plugin.configure(values[pluginID] ?? [:])
    }
  }

  // MARK: - Persistence

  private func loadSettings() {
    for plugin in registry.plugins {
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

// MARK: - Color Extension

extension Color {
  init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

    let red = Double((rgb & 0xFF0000) >> 16) / 255.0
    let green = Double((rgb & 0x00FF00) >> 8) / 255.0
    let blue = Double(rgb & 0x0000FF) / 255.0

    self.init(red: red, green: green, blue: blue)
  }

  func toHex() -> String {
    guard let components = NSColor(self).cgColor.components else { return "#007AFF" }
    let red = Int(components[0] * 255.0)
    let green = Int(components[1] * 255.0)
    let blue = Int(components[2] * 255.0)
    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}
