import SwiftUI

/// Helper extensions for SettingsView widget and plugin bindings
extension SettingsView {
  /// Binding to toggle a menu bar widget's visibility
  func menuBarVisibilityBinding(for widgetId: String) -> Binding<Bool> {
    Binding(
      get: { widgetRegistry.isMenuBarWidgetVisible(widgetId) },
      set: { widgetRegistry.setMenuBarVisibility(widgetId: widgetId, isVisible: $0) }
    )
  }

  /// Binding to toggle a menu widget's visibility
  func menuVisibilityBinding(for widgetId: String) -> Binding<Bool> {
    Binding(
      get: { widgetRegistry.isMenuWidgetVisible(widgetId) },
      set: { widgetRegistry.setMenuVisibility(widgetId: widgetId, isVisible: $0) }
    )
  }

  /// Binding to toggle a plugin's enabled state
  func pluginEnabledBinding(for plugin: AnyPlugin) -> Binding<Bool> {
    Binding(
      get: { plugin.isEnabled },
      set: { newValue in
        plugin.configure(with: ["enabled": newValue])
        // Also update our local values dict so settings stay in sync
        if values[plugin.id] == nil { values[plugin.id] = [:] }
        values[plugin.id]?["enabled"] = newValue
      }
    )
  }
}

// MARK: - Setting View Rendering

extension SettingsView {
  @ViewBuilder
  func settingView(for definition: SettingDefinition, host: any SettingsHost) -> some View {
    switch definition {
    case .slider(let key, let label, let range, let defaultValue, let step):
      sliderSettingView(
        label: label,
        value: binding(for: host.id, key: key, default: defaultValue),
        displayValue: getValue(for: host.id, key: key, default: defaultValue) as? Double ?? defaultValue,
        range: range,
        step: step
      )

    case .toggle(let key, let label, let defaultValue, let description):
      VStack(alignment: .leading, spacing: 2) {
        Toggle(label, isOn: binding(for: host.id, key: key, default: defaultValue))
        if let description {
          Text(description)
            .font(.caption)
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
      }

    case .text(let key, let label, let defaultValue):
      VStack(alignment: .leading) {
        Text(label).font(.subheadline)
        TextField("", text: binding(for: host.id, key: key, default: defaultValue))
          .textFieldStyle(.roundedBorder)
      }

    case .dropdown:
      dropdownSettingView(definition: definition, host: host)

    case .hotkey(let key, let label, let defaultValue):
      ShortcutRecorderView(
        label: label,
        shortcutString: binding(for: host.id, key: key, default: defaultValue)
      )

    case .color(let key, let label, let defaultValue):
      // Only gate on colorMode when the host explicitly declares it.
      // Hosts without a colorMode setting always show their color pickers.
      let hasColorMode = host.settings().definitions.contains { $0.key == "colorMode" }
      let colorMode = getValue(for: host.id, key: "colorMode", default: "dynamic") as? String ?? "dynamic"
      if !hasColorMode || colorMode == "custom" {
        VStack(alignment: .leading) {
          Text(label).font(.subheadline)
          ColorPicker(
            "",
            selection: colorBinding(for: host.id, key: key, default: defaultValue),
            supportsOpacity: false
          )
        }
      }

    case .section(let label, let description):
      sectionHeaderView(label: label, description: description)
    }
  }

  @ViewBuilder
  private func dropdownSettingView(
    definition: SettingDefinition, host: any SettingsHost
  ) -> some View {
    if case .dropdown(let key, let label, let options, let defaultValue, let description) = definition {
      let showCores = getValue(for: host.id, key: "showCores", default: false) as? Bool ?? false
      if key == "coreLayout" && !showCores {
        EmptyView()
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text(label).font(.subheadline)
          Picker("", selection: binding(for: host.id, key: key, default: defaultValue)) {
            ForEach(options, id: \.self) { option in
              Text(option.capitalized).tag(option)
            }
          }
          .pickerStyle(.menu)
          if let description {
            Text(description)
              .font(.caption)
              .foregroundColor(Color(NSColor.tertiaryLabelColor))
          }
        }
      }
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private func sectionHeaderView(label: String, description: String?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.headline)
        .foregroundColor(.secondary)
      if let description {
        Text(description)
          .font(.caption)
          .foregroundColor(Color(NSColor.tertiaryLabelColor))
      }
      Divider()
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
    settingsHost(for: pluginID)?.configure(with: values[pluginID] ?? [:])
  }

  func loadSettings() {
    for host in allSettingsHosts {
      if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(host.id)") {
        values[host.id] = saved
      } else {
        var defaults: [String: Any] = [:]
        for definition in host.settings().definitions {
          defaults[definition.key] = definition.defaultValue
        }
        values[host.id] = defaults
      }
    }
  }

  private func saveSettings(for pluginID: String) {
    if let pluginValues = values[pluginID] {
      UserDefaults.standard.set(pluginValues, forKey: "plugin.\(pluginID)")
    }
  }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: View {
  let label: String
  @Binding var shortcutString: String
  @State private var isRecording = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.subheadline)
      HStack(spacing: 8) {
        ShortcutField(
          shortcutString: $shortcutString,
          isRecording: $isRecording
        )
        .frame(height: 28)

        if isRecording {
          Button("Cancel") {
            isRecording = false
          }
          .buttonStyle(.borderless)
          .font(.caption)
        }
      }
    }
  }
}

// MARK: - ShortcutField (NSViewRepresentable with first responder key capture)

private struct ShortcutField: NSViewRepresentable {
  @Binding var shortcutString: String
  @Binding var isRecording: Bool

  func makeNSView(context: Context) -> ShortcutCaptureView {
    syncCaptureFlag(isRecording: isRecording, viewRecording: false)
    let view = ShortcutCaptureView()
    view.onShortcutCaptured = { display in
      shortcutString = display
      isRecording = false
    }
    view.onCancelRecording = {
      isRecording = false
    }
    return view
  }

  func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
    syncCaptureFlag(isRecording: isRecording, viewRecording: nsView.recording)
    nsView.shortcutDisplay = shortcutString
    nsView.recording = isRecording
    nsView.onShortcutCaptured = { display in
      shortcutString = display
      isRecording = false
    }
    nsView.onCancelRecording = {
      isRecording = false
    }
    if isRecording {
      nsView.window?.makeFirstResponder(nsView)
    }
    nsView.needsDisplay = true
  }

  static func dismantleNSView(_ nsView: ShortcutCaptureView, coordinator: ()) {
    if nsView.recording {
      KeyboardNavigation.shared.isCapturingShortcut = false
    }
  }

  /// Only the recording field (or one leaving recording) may touch the flag —
  /// other fields' updates must not clear it while a sibling is recording.
  private func syncCaptureFlag(isRecording: Bool, viewRecording: Bool) {
    if isRecording || viewRecording {
      KeyboardNavigation.shared.isCapturingShortcut = isRecording
    }
  }
}
