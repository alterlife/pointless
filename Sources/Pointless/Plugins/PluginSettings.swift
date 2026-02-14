import Foundation

/// Settings configuration for a plugin
struct PluginSettings {
  let definitions: [SettingDefinition]

  init(definitions: [SettingDefinition] = []) {
    self.definitions = definitions
  }
}

/// Definition of a single setting
enum SettingDefinition: Identifiable {
  case slider(key: String, label: String, range: ClosedRange<Double>, defaultValue: Double)
  case toggle(key: String, label: String, defaultValue: Bool)
  case hotkey(key: String, label: String, defaultValue: String)
  case text(key: String, label: String, defaultValue: String)
  case dropdown(key: String, label: String, options: [String], defaultValue: String)

  /// Extract common components (key, label, defaultValue) from any case
  private var components: (key: String, label: String, defaultValue: Any) {
    switch self {
    case .slider(let key, let label, _, let defaultValue):
      return (key, label, defaultValue)
    case .toggle(let key, let label, let defaultValue):
      return (key, label, defaultValue)
    case .hotkey(let key, let label, let defaultValue):
      return (key, label, defaultValue)
    case .text(let key, let label, let defaultValue):
      return (key, label, defaultValue)
    case .dropdown(let key, let label, _, let defaultValue):
      return (key, label, defaultValue)
    }
  }

  var id: String {
    components.key
  }

  var key: String {
    components.key
  }

  var label: String {
    components.label
  }

  var defaultValue: Any {
    components.defaultValue
  }
}
