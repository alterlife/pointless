import XCTest
@testable import PointlessCore
import SwiftUI
import Combine

// Mock plugin for testing
class MockPlugin: ObservableObject, Plugin {
  let id: String
  let name: String

  @Published var menuBarText = "MOCK"
  var startCalled = false
  var stopCalled = false
  var configuredValues: [String: Any] = [:]

  init(id: String = "test.mock", name: String = "Mock Plugin") {
    self.id = id
    self.name = name
  }

  var settings: PluginSettings {
    PluginSettings(definitions: [
      .slider(key: "interval", label: "Interval", range: 1.0...10.0, defaultValue: 5.0)
    ])
  }

  func configure(_ values: [String: Any]) {
    configuredValues = values
  }

  func start() {
    startCalled = true
  }

  func stop() {
    stopCalled = true
  }

  func detailView() -> AnyView {
    AnyView(Text("Mock Detail"))
  }
}

final class PluginProtocolTests: XCTestCase {
  func testPluginProperties() {
    let plugin = MockPlugin()

    XCTAssertEqual(plugin.id, "test.mock")
    XCTAssertEqual(plugin.name, "Mock Plugin")
    XCTAssertEqual(plugin.menuBarText, "MOCK")
  }

  func testPluginLifecycle() {
    let plugin = MockPlugin()

    XCTAssertFalse(plugin.startCalled)
    XCTAssertFalse(plugin.stopCalled)

    plugin.start()
    XCTAssertTrue(plugin.startCalled)

    plugin.stop()
    XCTAssertTrue(plugin.stopCalled)
  }

  func testPluginConfiguration() {
    let plugin = MockPlugin()

    plugin.configure(["interval": 3.0, "enabled": false])

    XCTAssertEqual(plugin.configuredValues["interval"] as? Double, 3.0)
    XCTAssertEqual(plugin.configuredValues["enabled"] as? Bool, false)
  }

  func testDefaultMenuBarView() {
    let plugin = MockPlugin()
    XCTAssertNil(plugin.menuBarView())
  }

  func testAnyPluginWrapper() {
    let plugin = MockPlugin()
    let wrapped = AnyPlugin(plugin)

    XCTAssertEqual(wrapped.id, plugin.id)
    XCTAssertEqual(wrapped.name, plugin.name)
    XCTAssertEqual(wrapped.menuBarText, plugin.menuBarText)
  }

  func testAnyPluginForwardsActions() {
    let plugin = MockPlugin()
    let wrapped = AnyPlugin(plugin)

    XCTAssertFalse(plugin.startCalled)
    wrapped.start()
    XCTAssertTrue(plugin.startCalled)

    wrapped.stop()
    XCTAssertTrue(plugin.stopCalled)

    wrapped.configure(["test": "value"])
    XCTAssertEqual(plugin.configuredValues["test"] as? String, "value")
  }
}

@MainActor
final class PluginRegistryTests: XCTestCase {
  func testEmptyRegistry() {
    let registry = PluginRegistry()
    XCTAssertTrue(registry.plugins.isEmpty)
  }

  func testRegisterPlugin() {
    let registry = PluginRegistry()
    let plugin = MockPlugin()

    registry.register(plugin)

    XCTAssertEqual(registry.plugins.count, 1)
    XCTAssertEqual(registry.plugins.first?.id, "test.mock")
  }

  func testDuplicatePluginRejection() {
    let registry = PluginRegistry()
    let plugin1 = MockPlugin()
    let plugin2 = MockPlugin() // Same ID

    registry.register(plugin1)
    registry.register(plugin2)

    // Should only have one plugin
    XCTAssertEqual(registry.plugins.count, 1)
  }

  func testMultiplePlugins() {
    let registry = PluginRegistry()
    let plugin1 = MockPlugin(id: "test.plugin1", name: "Plugin 1")
    let plugin2 = MockPlugin(id: "test.plugin2", name: "Plugin 2")

    registry.register(plugin1)
    registry.register(plugin2)

    XCTAssertEqual(registry.plugins.count, 2)
    XCTAssertTrue(registry.plugins.contains(where: { $0.id == "test.plugin1" }))
    XCTAssertTrue(registry.plugins.contains(where: { $0.id == "test.plugin2" }))
  }

  func testRegisterPluginArray() {
    let registry = PluginRegistry()
    let plugins: [any Plugin] = [
      MockPlugin(id: "test.1", name: "Plugin 1"),
      MockPlugin(id: "test.2", name: "Plugin 2")
    ]

    registry.register(plugins)

    XCTAssertEqual(registry.plugins.count, 2)
  }
}
