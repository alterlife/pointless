import SwiftUI

/// Helper extensions for SettingsView widget filtering
extension SettingsView {
  func getInactiveMenuBarWidgets() -> [MenuBarWidget] {
    getAllMenuBarWidgets().filter { !widgetRegistry.isMenuBarWidgetVisible($0.id) }
  }

  func getInactiveMenuWidgets() -> [MenuWidget] {
    getAllMenuWidgets().filter { !widgetRegistry.isMenuWidgetVisible($0.id) }
  }

  func getAllMenuBarWidgets() -> [MenuBarWidget] {
    pluginRegistry.plugins.flatMap { $0.menuBarWidgets() }
  }

  func getAllMenuWidgets() -> [MenuWidget] {
    pluginRegistry.plugins.flatMap { $0.menuWidgets() }
  }
}

// MARK: - Setting View Rendering

extension SettingsView {
  @ViewBuilder
  func settingView(for definition: SettingDefinition, plugin: AnyPlugin) -> some View {
    switch definition {
    case .slider(let key, let label, let range, let defaultValue, let step):
      sliderSettingView(
        label: label,
        value: binding(for: plugin.id, key: key, default: defaultValue),
        displayValue: getValue(for: plugin.id, key: key, default: defaultValue) as? Double ?? defaultValue,
        range: range,
        step: step
      )

    case .toggle(let key, let label, let defaultValue):
      Toggle(label, isOn: binding(for: plugin.id, key: key, default: defaultValue))

    case .text(let key, let label, let defaultValue):
      VStack(alignment: .leading) {
        Text(label).font(.subheadline)
        TextField("", text: binding(for: plugin.id, key: key, default: defaultValue))
          .textFieldStyle(.roundedBorder)
      }

    case .dropdown(let key, let label, let options, let defaultValue):
      let showCores = getValue(for: plugin.id, key: "showCores", default: false) as? Bool ?? false
      if key == "coreLayout" && !showCores {
        EmptyView()
      } else {
        VStack(alignment: .leading) {
          Text(label).font(.subheadline)
          Picker("", selection: binding(for: plugin.id, key: key, default: defaultValue)) {
            ForEach(options, id: \.self) { option in
              Text(option.capitalized).tag(option)
            }
          }
          .pickerStyle(.menu)
        }
      }

    case .hotkey(let key, let label, let defaultValue):
      VStack(alignment: .leading) {
        Text(label).font(.subheadline)
        TextField("Press shortcut...", text: binding(for: plugin.id, key: key, default: defaultValue))
          .textFieldStyle(.roundedBorder)
      }

    case .color(let key, let label, let defaultValue):
      let colorMode = getValue(for: plugin.id, key: "colorMode", default: "dynamic") as? String ?? "dynamic"
      if colorMode == "custom" {
        VStack(alignment: .leading) {
          Text(label).font(.subheadline)
          ColorPicker(
            "",
            selection: colorBinding(for: plugin.id, key: key, default: defaultValue),
            supportsOpacity: false
          )
        }
      }

    case .section(let label):
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .font(.headline)
          .foregroundColor(.secondary)
        Divider()
      }
    }
  }

  @ViewBuilder
  private func sliderSettingView(
    label: String,
    value: Binding<Double>,
    displayValue: Double,
    range: ClosedRange<Double>,
    step: Double
  ) -> some View {
    VStack(alignment: .leading) {
      Text(label).font(.subheadline)
      HStack {
        Slider(value: value, in: range, step: step)
        let format = step >= 1.0 ? "%.0f" : "%.1f"
        Text(String(format: format, displayValue))
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 40)
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
}

// MARK: - Bindings & Persistence

extension SettingsView {
  func binding<T>(for pluginID: String, key: String, default defaultValue: T) -> Binding<T> {
    Binding(
      get: { getValue(for: pluginID, key: key, default: defaultValue) as? T ?? defaultValue },
      set: { newValue in setValue(newValue, for: pluginID, key: key) }
    )
  }

  func getValue(for pluginID: String, key: String, default defaultValue: Any) -> Any {
    values[pluginID]?[key] ?? defaultValue
  }

  func setValue(_ value: Any, for pluginID: String, key: String) {
    if values[pluginID] == nil {
      values[pluginID] = [:]
    }
    values[pluginID]?[key] = value
    saveSettings(for: pluginID)
    if let plugin = pluginRegistry.plugins.first(where: { $0.id == pluginID }) {
      plugin.configure(values[pluginID] ?? [:])
    }
  }

  func loadSettings() {
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
