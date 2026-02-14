import Foundation
import Combine

/// Simple registry that holds all registered plugins
@MainActor
class PluginRegistry: ObservableObject {
  static let shared = PluginRegistry()

  @Published private(set) var plugins: [AnyPlugin] = []

  private init() {}

  /// Register a plugin
  func register<P: Plugin>(_ plugin: P) {
    registerWrapped(AnyPlugin(plugin))
  }

  /// Register multiple plugins
  func register(_ plugins: [any Plugin]) {
    for plugin in plugins {
      registerWrapped(AnyPlugin(plugin))
    }
  }

  /// Internal registration logic - accepts pre-wrapped plugin
  private func registerWrapped(_ wrapped: AnyPlugin) {
    // Check for duplicate IDs
    if plugins.contains(where: { $0.id == wrapped.id }) {
      print("⚠️ Plugin with ID '\(wrapped.id)' already registered. Skipping.")
      return
    }

    plugins.append(wrapped)
    print("✅ Registered plugin: \(wrapped.name) (\(wrapped.id))")
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

    // Scan for .bundle files
    guard let bundles = try? fileManager.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil)
      .filter({ $0.pathExtension == "bundle" })
    else {
      return
    }

    for bundleURL in bundles {
      loadBundle(at: bundleURL)
    }
  }

  private func loadBundle(at url: URL) {
    guard let bundle = Bundle(url: url) else {
      print("⚠️ Failed to create bundle from: \(url.path)")
      return
    }

    guard bundle.load() else {
      print("⚠️ Failed to load bundle: \(url.lastPathComponent)")
      return
    }

    guard let principalClass = bundle.principalClass as? NSObject.Type else {
      print("⚠️ Bundle principal class is not NSObject: \(url.lastPathComponent)")
      return
    }

    guard let plugin = principalClass.init() as? any Plugin else {
      print("⚠️ Bundle principal class does not conform to Plugin: \(url.lastPathComponent)")
      return
    }

    registerWrapped(AnyPlugin(plugin))
  }
}
