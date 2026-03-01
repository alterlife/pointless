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
      ShortcutRecorderView(
        label: label,
        shortcutString: binding(for: plugin.id, key: key, default: defaultValue)
      )

    case .color(let key, let label, let defaultValue):
      // Only gate on colorMode when the plugin explicitly declares it.
      // Plugins without a colorMode setting always show their color pickers.
      let hasColorMode = plugin.settings().definitions.contains { $0.key == "colorMode" }
      let colorMode = getValue(for: plugin.id, key: "colorMode", default: "dynamic") as? String ?? "dynamic"
      if !hasColorMode || colorMode == "custom" {
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

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: View {
  let label: String
  @Binding var shortcutString: String
  @State private var isRecording = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.subheadline)
      HStack(spacing: 8) {
        ZStack {
          Text(isRecording ? "Press shortcut..." : shortcutString)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(isRecording ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
              isRecording
                ? Color.accentColor.opacity(0.1)
                : Color(NSColor.controlBackgroundColor)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(
                  isRecording ? Color.accentColor : Color(NSColor.separatorColor),
                  lineWidth: isRecording ? 2 : 1
                )
            )
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture { isRecording = true }
        }
        .background(
          ShortcutKeyListener(isRecording: $isRecording) { display in
            shortcutString = display
            isRecording = false
          }
        )

        if isRecording {
          Button("Cancel") { isRecording = false }
            .buttonStyle(.borderless)
            .font(.caption)
        }
      }
    }
  }
}

// MARK: - Key Listener (NSViewRepresentable)

private struct ShortcutKeyListener: NSViewRepresentable {
  @Binding var isRecording: Bool
  let onCapture: (String) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.parentView = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isRecording = isRecording
    context.coordinator.onCapture = onCapture
    if isRecording {
      context.coordinator.startMonitoring()
    } else {
      context.coordinator.stopMonitoring()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture)
  }

  class Coordinator {
    var isRecording = false
    var onCapture: (String) -> Void
    var parentView: NSView?
    private var monitor: Any?

    init(onCapture: @escaping (String) -> Void) {
      self.onCapture = onCapture
    }

    deinit { stopMonitoring() }

    func startMonitoring() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.isRecording else { return event }
        let modifiers = event.modifierFlags.intersection(
          [.command, .shift, .option, .control]
        )
        // Require at least one modifier for a valid shortcut
        guard !modifiers.isEmpty else {
          // ESC cancels recording
          if event.keyCode == 53 {
            self.isRecording = false
            return nil
          }
          return event
        }
        let display = Self.modifierSymbols(modifiers) + Self.keyName(from: event)
        self.onCapture(display)
        return nil
      }
    }

    func stopMonitoring() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
      var result = ""
      if flags.contains(.control) { result += "\u{2303}" }
      if flags.contains(.option) { result += "\u{2325}" }
      if flags.contains(.shift) { result += "\u{21E7}" }
      if flags.contains(.command) { result += "\u{2318}" }
      return result
    }

    static func keyName(from event: NSEvent) -> String {
      switch event.keyCode {
      case 49: return "Space"
      case 36: return "Return"
      case 48: return "Tab"
      case 51: return "Delete"
      case 53: return "Esc"
      case 123: return "\u{2190}"
      case 124: return "\u{2192}"
      case 125: return "\u{2193}"
      case 126: return "\u{2191}"
      default:
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key\(event.keyCode)"
      }
    }
  }
}
