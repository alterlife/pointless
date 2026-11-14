import XCTest
@testable import PointlessCore
import SwiftUI
import Combine

// Mock widget source for testing — stands in for both plugins and navigation
@MainActor
final class MockWidgetSource: ObservableObject, WidgetSource {
  let id: String
  let icon: String
  @Published var isEnabled: Bool

  private let barWidgetList: [MenuBarWidget]
  private let menuWidgetList: [MenuWidget]

  init(
    id: String,
    icon: String = "puzzlepiece",
    isEnabled: Bool = true,
    barWidgetIds: [String] = ["bar"],
    menuWidgetIds: [String] = ["menu"]
  ) {
    self.id = id
    self.icon = icon
    self.isEnabled = isEnabled
    self.barWidgetList = barWidgetIds.map { widgetId in
      MenuBarWidget(id: "\(id).\(widgetId)", ownerId: id, name: widgetId) { Text(widgetId) }
    }
    self.menuWidgetList = menuWidgetIds.map { widgetId in
      MenuWidget(id: "\(id).\(widgetId)", ownerId: id, name: widgetId) { Text(widgetId) }
    }
  }

  func menuBarWidgets() -> [MenuBarWidget] { barWidgetList }
  func menuWidgets() -> [MenuWidget] { menuWidgetList }
}

@MainActor
final class WidgetRegistryTests: XCTestCase {
  private var registry: WidgetRegistry!
  private var savedConfigs: Data?
  /// The registry holds sources weakly — tests must keep them alive.
  private var retainedSources: [MockWidgetSource] = []

  override func setUp() {
    super.setUp()
    savedConfigs = UserDefaults.standard.data(forKey: "pointless.widgetConfigs")
    retainedSources = []
    registry = WidgetRegistry()
  }

  override func tearDown() {
    if let savedConfigs {
      UserDefaults.standard.set(savedConfigs, forKey: "pointless.widgetConfigs")
    } else {
      UserDefaults.standard.removeObject(forKey: "pointless.widgetConfigs")
    }
    registry = nil
    retainedSources = []
    super.tearDown()
  }

  @discardableResult
  private func makeSource(_ source: MockWidgetSource) -> MockWidgetSource {
    retainedSources.append(source)
    registry.registerSource(source)
    return source
  }

  func testEnabledSourceWidgetsAreOrdered() {
    makeSource(MockWidgetSource(id: "test.source"))

    XCTAssertEqual(registry.orderedMenuBarWidgets.map(\.id), ["test.source.bar"])
    XCTAssertEqual(registry.orderedMenuWidgets.map(\.id), ["test.source.menu"])
    XCTAssertTrue(registry.sourceIsEnabled("test.source"))
    XCTAssertEqual(registry.sourceIcon("test.source"), "puzzlepiece")
  }

  func testDisabledSourceWidgetsAreSortedButNotOrdered() {
    makeSource(MockWidgetSource(id: "test.source", isEnabled: false))

    XCTAssertTrue(registry.orderedMenuBarWidgets.isEmpty)
    XCTAssertTrue(registry.orderedMenuWidgets.isEmpty)
    XCTAssertEqual(registry.sortedAllMenuBarWidgets.map(\.id), ["test.source.bar"])
    XCTAssertFalse(registry.sourceIsEnabled("test.source"))
  }

  /// Regression: navigation is not a plugin — its widgets must survive alongside
  /// plugin widgets instead of being wiped when another source registers.
  func testMultipleSourcesCoexist() {
    makeSource(MockWidgetSource(id: "test.nav", icon: "keyboard"))
    makeSource(MockWidgetSource(id: "test.plugin"))

    XCTAssertEqual(
      Set(registry.orderedMenuBarWidgets.map(\.ownerId)),
      ["test.nav", "test.plugin"]
    )
    XCTAssertEqual(registry.sourceIcon("test.nav"), "keyboard")
  }

  func testDuplicateSourceIdRejected() {
    makeSource(MockWidgetSource(id: "test.dup"))
    makeSource(MockWidgetSource(id: "test.dup", barWidgetIds: ["other"]))

    XCTAssertEqual(registry.sortedAllMenuBarWidgets.map(\.id), ["test.dup.bar"])
  }

  func testTogglingSourceEnabledRebuildsWidgets() async {
    let source = makeSource(MockWidgetSource(id: "test.toggle"))
    XCTAssertEqual(registry.orderedMenuBarWidgets.count, 1)

    source.isEnabled = false
    // Rebuild is deferred a run-loop turn past objectWillChange (willSet timing)
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(registry.orderedMenuBarWidgets.isEmpty)
    XCTAssertEqual(registry.sortedAllMenuBarWidgets.count, 1)
  }

  func testSetMenuBarVisibilityHidesWidget() {
    makeSource(MockWidgetSource(id: "test.vis"))

    registry.setMenuBarVisibility(widgetId: "test.vis.bar", isVisible: false)

    XCTAssertTrue(registry.orderedMenuBarWidgets.isEmpty)
    XCTAssertFalse(registry.isMenuBarWidgetVisible("test.vis.bar"))
    XCTAssertEqual(registry.sortedAllMenuBarWidgets.count, 1)
  }

  func testUnknownSourceReportsDisabled() {
    XCTAssertFalse(registry.sourceIsEnabled("test.nonexistent"))
    XCTAssertNil(registry.sourceIcon("test.nonexistent"))
  }
}
