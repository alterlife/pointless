import Foundation

/// Anything that exposes declarative settings and accepts configuration values —
/// the core navigation feature and plugins alike. The Settings UI renders hosts
/// generically and persists their values under `plugin.<id>`.
@MainActor
protocol SettingsHost: AnyObject {
  var id: String { get }
  var name: String { get }
  func settings() -> PluginSettings
  func configure(with values: [String: Any])
}

extension AnyPlugin: SettingsHost {}
extension KeyboardNavigation: SettingsHost {}
