import Combine
import Foundation
import OSLog

/// Simple registry that holds all registered plugins
@MainActor
class PluginRegistry: ObservableObject {
  static let shared = PluginRegistry()

  @Published private(set) var plugins: [AnyPlugin] = []
  private var cancellables = Set<AnyCancellable>()

  init() {}

  /// Register a plugin — wraps it for type erasure and adds it to the list
  func register<P: Plugin>(_ plugin: P) {
    register(AnyPlugin(plugin))
  }

  /// Register multiple plugins
  func register(_ plugins: [any Plugin]) {
    plugins.forEach { register(AnyPlugin($0)) }
  }

  private func register(_ plugin: AnyPlugin) {
    guard !plugins.contains(where: { $0.id == plugin.id }) else {
      Logger.warning("Plugin with ID '\(plugin.id)' already registered. Skipping.")
      return
    }

    plugin.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
    .store(in: &cancellables)

    plugins.append(plugin)
    WidgetRegistry.shared.registerSource(plugin)
    Logger.info("Registered plugin: \(plugin.name) (\(plugin.id))", logger: Logger.pluginRegistry)
  }

  /// Load external plugins from bundles
  func loadExternalPlugins() {
    let fileManager = FileManager.default
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }

    let pluginsDir = appSupport.appendingPathComponent("Pointless/Plugins")

    // Create directory if it doesn't exist
    try? fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

    guard let bundles = try? fileManager.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil)
      .filter({ $0.pathExtension == "bundle" })
    else {
      return
    }

    for bundleURL in bundles {
      loadBundle(at: bundleURL)
    }
  }

  func suspendAll() {
    plugins.forEach { $0.suspend() }
  }

  func resumeAll() {
    plugins.forEach { $0.resume() }
  }

  private func loadBundle(at url: URL) {
    guard let bundle = Bundle(url: url) else {
      Logger.error("Failed to create bundle from: \(url.path)")
      return
    }

    guard bundle.load() else {
      Logger.error("Failed to load bundle: \(url.lastPathComponent)")
      return
    }

    guard let principalClass = bundle.principalClass as? NSObject.Type else {
      Logger.error("Bundle principal class is not NSObject: \(url.lastPathComponent)")
      return
    }

    guard let plugin = principalClass.init() as? any Plugin else {
      Logger.error("Bundle principal class does not conform to Plugin: \(url.lastPathComponent)")
      return
    }

    register(AnyPlugin(plugin))
  }
}
