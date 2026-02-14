import Combine
import SwiftUI

/// Protocol for autonomous plugins
/// Plugins are active and self-contained - they manage their own data, timing, and views
protocol Plugin: ObservableObject {
  /// Unique identifier (e.g., "pointless.cpu")
  var id: String { get }

  /// Display name (e.g., "CPU")
  var name: String { get }

  /// Text displayed in menu bar (fallback if menuBarView returns nil)
  var menuBarText: String { get }

  /// Initialize plugin (setup settings, timers, etc.)
  func initialize()

  /// Settings definitions for this plugin
  func settings() -> PluginSettings

  /// Custom view for menu bar display (optional - full rendering control)
  /// Return nil to use menuBarText instead
  func menuBarView() -> NSView?

  /// Detailed view shown in menu
  func detailView() -> AnyView

  /// Configure plugin with saved settings values
  func configure(_ values: [String: Any])

  /// Start the plugin (plugin starts its own updates)
  func start()

  /// Stop the plugin
  func stop()
}

// Default implementation for menuBarView - plugins can opt-in to custom views
extension Plugin {
  /// Default: use menuBarText instead of custom view
  func menuBarView() -> NSView? {
    nil
  }

  /// Default: simple text view with plugin name
  func detailView() -> AnyView {
    AnyView(Text(name))
  }

  /// Default: no initialization needed
  func initialize() { }
}

// Type-erased wrapper for Plugin to use in arrays
class AnyPlugin: ObservableObject {
  let id: String
  let name: String

  private let _menuBarText: () -> String
  private let _menuBarView: () -> NSView?
  private let _detailView: () -> AnyView
  private let _settings: () -> PluginSettings
  private let _configure: ([String: Any]) -> Void
  private let _start: () -> Void
  private let _stop: () -> Void
  private let _objectWillChange: () -> ObservableObjectPublisher

  var menuBarText: String {
    _menuBarText()
  }

  func settings() -> PluginSettings {
    _settings()
  }

  init<P: Plugin>(_ plugin: P) {
    self.id = plugin.id
    self.name = plugin.name
    self._menuBarText = { plugin.menuBarText }
    self._menuBarView = { plugin.menuBarView() }
    self._detailView = { plugin.detailView() }
    self._settings = { plugin.settings() }
    self._configure = { plugin.configure($0) }
    self._start = { plugin.start() }
    self._stop = { plugin.stop() }

    // Type-erased publisher - conditional cast with clear error
    let publisher = plugin.objectWillChange
    self._objectWillChange = {
      guard let typedPublisher = publisher as? ObservableObjectPublisher else {
        fatalError("Plugin \(plugin.id) does not use ObservableObjectPublisher")
      }
      return typedPublisher
    }

    // Forward objectWillChange from wrapped plugin to this wrapper
    plugin.objectWillChange.sink { [weak self] _ in
      guard let self = self else { return }
      self.objectWillChange.send()
    }
    .store(in: &cancellables)
  }

  private var cancellables: Set<AnyCancellable> = []

  func menuBarView() -> NSView? {
    _menuBarView()
  }

  func detailView() -> AnyView {
    _detailView()
  }

  func configure(_ values: [String: Any]) {
    _configure(values)
  }

  func start() {
    _start()
  }

  func stop() {
    _stop()
  }
}

/// SwiftUI wrapper that observes a plugin and re-renders when it changes
struct ObservablePluginView: View {
  @ObservedObject var plugin: AnyPlugin
  let content: (AnyPlugin) -> AnyView

  var body: some View {
    content(plugin)
  }
}
