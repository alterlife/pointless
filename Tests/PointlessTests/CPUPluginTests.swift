import Combine
@testable import PointlessCore
import XCTest

@MainActor
final class CPUPluginTests: XCTestCase {
  func testTotalUsageChangeFiresObjectWillChange() {
    let plugin = CPUPlugin()
    var changeCount = 0
    let cancellable = plugin.objectWillChange.sink {
      changeCount += 1
    }

    plugin.totalUsage = 0.75
    XCTAssertEqual(changeCount, 1)
    _ = cancellable
  }

  func testHistoryChangeFiresObjectWillChange() {
    let plugin = CPUPlugin()
    var changeCount = 0
    let cancellable = plugin.objectWillChange.sink {
      changeCount += 1
    }

    plugin.history.append(0.5)
    XCTAssertEqual(changeCount, 1)
    _ = cancellable
  }

  func testCoreUsagesChangeFiresObjectWillChange() {
    let plugin = CPUPlugin()
    var changeCount = 0
    let cancellable = plugin.objectWillChange.sink {
      changeCount += 1
    }

    plugin.coreUsages = [0.25, 0.50]
    XCTAssertEqual(changeCount, 1)
    _ = cancellable
  }

  func testAnyPluginForwardsCPUChanges() {
    let plugin = CPUPlugin()
    let wrapped = AnyPlugin(plugin)
    var changeCount = 0
    let cancellable = wrapped.objectWillChange.sink {
      changeCount += 1
    }

    plugin.totalUsage = 0.90
    XCTAssertEqual(changeCount, 1)
    _ = cancellable
  }
}
