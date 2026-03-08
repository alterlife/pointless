import Combine
import SwiftUI

// MARK: - Plugin Protocol

/// A self-contained plugin that provides data, views, and widgets to Pointless.
///
/// Plugins manage their own state, timers, and update cycles. The app shell only
/// registers them, starts them, and gives them space in the menu bar and menu.
protocol Plugin: ObservableObject {
  /// Unique reverse-DNS identifier, e.g. `"pointless.cpu"`
  var id: String { get }

  /// Human-readable name shown in settings, e.g. `"CPU"`
  var name: String { get }

  /// SF Symbol for the settings tab icon, e.g. `"cpu"`, `"keyboard"`
  var icon: String { get }

  /// Fallback text for the menu bar when `menuBarView()` returns nil
  var menuBarText: String { get }

  /// Whether this plugin is currently active
  var isEnabled: Bool { get set }

  /// One-time setup: declare settings and register update actions.
  /// Called during `init` — not by the app shell.
  func initialize()

  /// The settings this plugin exposes in the Settings UI
  func settings() -> PluginSettings

  /// Optional custom NSView for the menu bar. Return nil to use `menuBarText`.
  func menuBarView() -> NSView?

  /// The view shown inside the dropdown menu for this plugin
  func detailView() -> AnyView

  /// Apply a settings dictionary to this plugin's `@Published` properties
  func configure(with values: [String: Any])

  func start()
  func stop()
  func suspend()
  func resume()

  func menuBarWidgets() -> [MenuBarWidget]
  func menuWidgets() -> [MenuWidget]
}

// MARK: - Protocol Defaults

extension Plugin {
  var icon: String { "puzzlepiece" }
  func menuBarView() -> NSView? { nil }
  func detailView() -> AnyView { AnyView(Text(name)) }
  func initialize() {}
  func menuBarWidgets() -> [MenuBarWidget] { [] }
  func menuWidgets() -> [MenuWidget] { [] }
}

// MARK: - Type Erasure

/// A type-erased `Plugin` that forwards all calls to the underlying concrete plugin.
/// Used so heterogeneous plugins can live in a single array.
class AnyPlugin: ObservableObject {
  let id: String
  let name: String
  let icon: String

  private let _menuBarText: () -> String
  private let _isEnabled: () -> Bool
  private let _menuBarView: () -> NSView?
  private let _detailView: () -> AnyView
  private let _settings: () -> PluginSettings
  private let _configure: ([String: Any]) -> Void
  private let _start: () -> Void
  private let _stop: () -> Void
  private let _suspend: () -> Void
  private let _resume: () -> Void
  private let _menuBarWidgets: () -> [MenuBarWidget]
  private let _menuWidgets: () -> [MenuWidget]

  private var cancellables: Set<AnyCancellable> = []

  init<P: Plugin>(_ plugin: P) {
    id   = plugin.id
    name = plugin.name
    icon = plugin.icon

    _menuBarText    = { plugin.menuBarText }
    _isEnabled      = { plugin.isEnabled }
    _menuBarView    = { plugin.menuBarView() }
    _detailView     = { plugin.detailView() }
    _settings       = { plugin.settings() }
    _configure      = { plugin.configure(with: $0) }
    _start          = { plugin.start() }
    _stop           = { plugin.stop() }
    _suspend        = { plugin.suspend() }
    _resume         = { plugin.resume() }
    _menuBarWidgets = { plugin.menuBarWidgets() }
    _menuWidgets    = { plugin.menuWidgets() }

    // Relay the wrapped plugin's changes so SwiftUI re-renders any observing views
    plugin.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
    .store(in: &cancellables)
  }

  var menuBarText: String { _menuBarText() }
  var isEnabled: Bool { _isEnabled() }

  func settings() -> PluginSettings { _settings() }
  func menuBarView() -> NSView? { _menuBarView() }
  func detailView() -> AnyView { _detailView() }
  func configure(with values: [String: Any]) { _configure(values) }
  func start() { _start() }
  func stop() { _stop() }
  func suspend() { _suspend() }
  func resume() { _resume() }
  func menuBarWidgets() -> [MenuBarWidget] { _menuBarWidgets() }
  func menuWidgets() -> [MenuWidget] { _menuWidgets() }
}

// MARK: - Observable Plugin View

/// Wraps a plugin in an `@ObservedObject` so SwiftUI re-renders when the plugin's data changes.
///
/// Without this wrapper, SwiftUI doesn't observe plugins stored in arrays
/// and the UI freezes after the initial render.
struct ObservablePluginView: View {
  @ObservedObject var plugin: AnyPlugin
  let content: (AnyPlugin) -> AnyView

  var body: some View {
    content(plugin)
  }
}
