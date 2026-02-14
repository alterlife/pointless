import SwiftUI

/// Auto-generated settings UI from plugin definitions
public struct SettingsView: View {
  public init() {}

  @ObservedObject var registry = PluginRegistry.shared
  @State private var values: [String: [String: Any]] = [:]

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Settings")
          .font(.title)
          .fontWeight(.bold)
          .padding(.bottom, 8)

        ForEach(registry.plugins, id: \.id) { plugin in
          pluginSection(for: plugin)
        }
      }
      .padding()
    }
    .frame(minWidth: 400, minHeight: 300)
    .onAppear {
      loadSettings()
    }
  }

  @ViewBuilder
  private func pluginSection(for plugin: AnyPlugin) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(plugin.name)
        .font(.headline)

      if plugin.settings().definitions.isEmpty {
        Text("No settings available")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        ForEach(plugin.settings().definitions) { definition in
          settingView(for: definition, plugin: plugin)
        }
      }

      Divider()
    }
  }

  @ViewBuilder
  private func settingView(for definition: SettingDefinition, plugin: AnyPlugin) -> some View {
    switch definition {
    case .slider(let key, let label, let range, let defaultValue):
      VStack(alignment: .leading) {
        Text(label)
          .font(.subheadline)
        HStack {
          Slider(
            value: binding(for: plugin.id, key: key, default: defaultValue),
            in: range
          )
          Text(String(
            format: "%.1f",
            getValue(for: plugin.id, key: key, default: defaultValue) as? Double ?? defaultValue
          ))
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
    }
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
        // Initialize with defaults
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
