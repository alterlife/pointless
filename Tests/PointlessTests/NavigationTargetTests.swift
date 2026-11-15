import XCTest
@testable import PointlessCore
import ApplicationServices
import CoreGraphics

final class NavigationTargetTests: XCTestCase {
  private func axElement() -> AXElement {
    AXElement(raw: AXUIElementCreateApplication(getpid()))
  }

  private func node(_ id: Int, parent: AXTreeNode? = nil) -> AXTreeNode {
    AXTreeNode(id: id, element: axElement(), parent: parent)
  }

  private func element(
    _ frame: CGRect,
    role: String = "AXButton",
    node: AXTreeNode? = nil,
    groupingAncestor: GroupingAncestor = .walkNode(0)
  ) -> NavigationTarget {
    NavigationTarget(
      element: axElement(),
      screenFrame: frame,
      role: role,
      screen: NSScreen.screens[0],
      groupingAncestor: groupingAncestor,
      node: node
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

    let result = ElementDiscovery.deduplicateAndRegroup([outer, inner], mode: .scrollable)

    XCTAssertEqual(result.count, 2)
  }

  func testInteractiveScanMergesSameAnchors() {
    let container = element(CGRect(x: 100, y: 300, width: 200, height: 200))
    let control = element(CGRect(x: 100, y: 480, width: 40, height: 20))

    let result = ElementDiscovery.deduplicateAndRegroup([container, control], mode: .interactive)

    XCTAssertEqual(result.count, 1)
  }

  func testMergedWrappersDoNotLeaveSingletonGroups() {
    // Root node 1 holds 28 clickable wrappers, each holding a button at its top-left.
    let root = node(1)
    var elements: [NavigationTarget] = []
    for index in 0..<28 {
      let wrapper = node(2 + index * 2, parent: root)
      let button = node(wrapper.id + 1, parent: wrapper)
      let originX = CGFloat(index) * 50
      elements.append(element(
        CGRect(x: originX, y: 300, width: 40, height: 40),
        node: wrapper, groupingAncestor: .walkNode(root.id)
      ))
      elements.append(element(
        CGRect(x: originX, y: 320, width: 20, height: 20),
        node: button, groupingAncestor: .walkNode(wrapper.id)
      ))
    }

    let result = ElementDiscovery.deduplicateAndRegroup(elements, mode: .interactive)

    XCTAssertEqual(result.count, 28)
    XCTAssertTrue(result.allSatisfy { $0.groupingAncestor == .walkNode(1) })
  }

  func testRegroupKeepsAncestorWithMultipleDiscoveries() {
    // Node 2 (under root 1) holds two buttons; node 3 (under root 1) wraps a single button.
    let root = node(1)
    let node2 = node(2, parent: root)
    let node3 = node(3, parent: root)
    let node4 = node(4, parent: node2)
    let node5 = node(5, parent: node2)
    let node6 = node(6, parent: node3)
    let elements = [
      element(CGRect(x: 0, y: 0, width: 10, height: 10),
              node: node4, groupingAncestor: .walkNode(2)),
      element(CGRect(x: 20, y: 0, width: 10, height: 10),
              node: node5, groupingAncestor: .walkNode(2)),
      element(CGRect(x: 40, y: 0, width: 10, height: 10),
              node: node6, groupingAncestor: .walkNode(3))
    ]

    let result = elements.regroupedForLabels()

    XCTAssertEqual(result.map(\.groupingAncestor), [.walkNode(2), .walkNode(2), .walkNode(1)])
  }
}
