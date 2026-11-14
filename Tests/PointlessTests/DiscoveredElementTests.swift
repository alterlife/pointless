import XCTest
@testable import PointlessCore
import ApplicationServices
import CoreGraphics

final class DiscoveredElementTests: XCTestCase {
  private func element(
    _ frame: CGRect,
    role: String = "AXButton",
    parentNode: Int = 1,
    walkNodeID: Int? = nil
  ) -> DiscoveredElement {
    DiscoveredElement(
      element: AXElement(raw: AXUIElementCreateApplication(getpid())),
      screenFrame: frame,
      role: role,
      screen: NSScreen.screens[0],
      groupingAncestor: .walkNode(parentNode),
      walkNodeID: walkNodeID
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

  // MARK: deduplicateAndRegroup

  func testScrollScanKeepsSameAnchorAreas() {
    // Inner area is below beginScroll's 50pt minimum — merging must not drop the outer one.
    let outer = element(CGRect(x: 100, y: 100, width: 600, height: 400), role: "AXScrollArea")
    let inner = element(CGRect(x: 100, y: 400, width: 40, height: 100), role: "AXScrollArea")

    let result = ElementDiscovery.deduplicateAndRegroup([outer, inner], mode: .scrollable, nodeParent: [:])

    XCTAssertEqual(result.count, 2)
  }

  func testInteractiveScanMergesSameAnchors() {
    let container = element(CGRect(x: 100, y: 300, width: 200, height: 200))
    let control = element(CGRect(x: 100, y: 480, width: 40, height: 20))

    let result = ElementDiscovery.deduplicateAndRegroup([container, control], mode: .interactive, nodeParent: [:])

    XCTAssertEqual(result.count, 1)
  }

  func testMergedWrappersDoNotLeaveSingletonGroups() {
    // Root node 1 holds 28 clickable wrappers, each holding a button at its top-left.
    var nodeParent: [Int: Int] = [1: 0]
    var elements: [DiscoveredElement] = []
    for index in 0..<28 {
      let wrapperNode = 2 + index * 2
      let buttonNode = wrapperNode + 1
      nodeParent[wrapperNode] = 1
      nodeParent[buttonNode] = wrapperNode
      let originX = CGFloat(index) * 50
      elements.append(element(
        CGRect(x: originX, y: 300, width: 40, height: 40), parentNode: 1, walkNodeID: wrapperNode
      ))
      elements.append(element(
        CGRect(x: originX, y: 320, width: 20, height: 20), parentNode: wrapperNode, walkNodeID: buttonNode
      ))
    }

    let result = ElementDiscovery.deduplicateAndRegroup(elements, mode: .interactive, nodeParent: nodeParent)

    XCTAssertEqual(result.count, 28)
    XCTAssertTrue(result.allSatisfy { $0.groupingAncestor == .walkNode(1) })
  }

  func testRegroupKeepsAncestorWithMultipleDiscoveries() {
    // Node 2 (under root 1) holds two buttons; node 3 (under root 1) wraps a single button.
    let nodeParent = [1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3]
    let elements = [
      element(CGRect(x: 0, y: 0, width: 10, height: 10), parentNode: 2, walkNodeID: 4),
      element(CGRect(x: 20, y: 0, width: 10, height: 10), parentNode: 2, walkNodeID: 5),
      element(CGRect(x: 40, y: 0, width: 10, height: 10), parentNode: 3, walkNodeID: 6)
    ]

    let result = elements.regroupedForLabels(nodeParent: nodeParent)

    XCTAssertEqual(result.map(\.groupingAncestor), [.walkNode(2), .walkNode(2), .walkNode(1)])
  }
}
