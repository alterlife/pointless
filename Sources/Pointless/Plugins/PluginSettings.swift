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
  case slider(key: String, label: String, range: ClosedRange<Double>, defaultValue: Double, step: Double = 0.1)
  case toggle(key: String, label: String, defaultValue: Bool, description: String? = nil)
  case hotkey(key: String, label: String, defaultValue: String)
  case text(key: String, label: String, defaultValue: String)
  case dropdown(key: String, label: String, options: [String], defaultValue: String, description: String? = nil)
  case color(key: String, label: String, defaultValue: String)
  case section(label: String, description: String? = nil)

  var id: String {
    switch self {
    case .section(let label, _):
      return "section.\(label)"
    default:
      return key
    }
  }

  var key: String {
    switch self {
    case .slider(let key, _, _, _, _),
         .toggle(let key, _, _, _),
         .hotkey(let key, _, _),
         .text(let key, _, _),
         .dropdown(let key, _, _, _, _),
         .color(let key, _, _):
      return key
    case .section:
      return ""
    }
  }

  var label: String {
    switch self {
    case .slider(_, let label, _, _, _),
         .toggle(_, let label, _, _),
         .hotkey(_, let label, _),
         .text(_, let label, _),
         .dropdown(_, let label, _, _, _),
         .color(_, let label, _):
      return label
    case .section(let label, _):
      return label
    }
  }

  var defaultValue: Any {
    switch self {
    case .slider(_, _, _, let defaultValue, _):
      return defaultValue
    case .toggle(_, _, let defaultValue, _):
      return defaultValue
    case .hotkey(_, _, let defaultValue):
      return defaultValue
    case .text(_, _, let defaultValue):
      return defaultValue
    case .dropdown(_, _, _, let defaultValue, _):
      return defaultValue
    case .color(_, _, let defaultValue):
      return defaultValue
    case .section:
      return ""
    }
  }
}
