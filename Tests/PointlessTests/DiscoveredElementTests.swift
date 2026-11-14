import XCTest
@testable import PointlessCore
import ApplicationServices
import CoreGraphics

final class DiscoveredElementTests: XCTestCase {
  private func element(_ frame: CGRect, role: String = "AXButton") -> DiscoveredElement {
    DiscoveredElement(
      element: AXElement(raw: AXUIElementCreateApplication(getpid())),
      screenFrame: frame,
      role: role,
      screen: NSScreen.screens[0],
      groupingAncestor: .walkNode(1)
    )
  }

  // Anchor = visual top-left: same minX and same maxY (NSScreen coords).

  func testSameAnchorKeepsSmallerFrame() {
    // Both frames share minX=100, maxY=500 — different sizes.
    let container = element(CGRect(x: 100, y: 300, width: 200, height: 200))
    let control = element(CGRect(x: 100, y: 480, width: 40, height: 20))

    let result = [container, control].mergeSharedAnchors()

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].screenFrame.width, 40)
  }

  func testDifferentAnchorsBothKept() {
    let a = element(CGRect(x: 100, y: 400, width: 50, height: 20))
    let b = element(CGRect(x: 300, y: 400, width: 50, height: 20))

    XCTAssertEqual([a, b].mergeSharedAnchors().count, 2)
  }

  func testSameLeftEdgeDifferentTopBothKept() {
    // Same minX but different maxY → different visual tops → different anchors.
    let tall = element(CGRect(x: 100, y: 300, width: 50, height: 200))  // maxY 500
    let short = element(CGRect(x: 100, y: 450, width: 50, height: 20))  // maxY 470

    XCTAssertEqual([tall, short].mergeSharedAnchors().count, 2)
  }
}
