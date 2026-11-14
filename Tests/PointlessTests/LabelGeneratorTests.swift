import XCTest
@testable import PointlessCore
import ApplicationServices
import CoreGraphics

final class LabelGeneratorTests: XCTestCase {
  private func element(groupingAncestor: GroupingAncestor, x: CGFloat = 0) -> DiscoveredElement {
    DiscoveredElement(
      element: AXElement(raw: AXUIElementCreateApplication(getpid())),
      screenFrame: CGRect(x: x, y: 0, width: 10, height: 10),
      role: "AXButton",
      screen: NSScreen.screens[0],
      groupingAncestor: groupingAncestor
    )
  }

  private func makeElements(count: Int, groups: Int) -> [DiscoveredElement] {
    (0..<count).map { element(groupingAncestor: .walkNode($0 % groups), x: CGFloat($0) * 20) }
  }

  // MARK: Flat labeling

  func testFewElementsGetSingleCharLabels() {
    let labeled = LabelGenerator.label(makeElements(count: 10, groups: 3))
    XCTAssertTrue(labeled.allSatisfy { $0.label.count == 1 })
    XCTAssertEqual(labeled[0].label, "a")
  }

  func testSingleGroupFallsBackToFlat() {
    // 30 elements but all one group — a prefix would narrow nothing.
    let labeled = LabelGenerator.label(makeElements(count: 30, groups: 1))
    XCTAssertTrue(labeled.allSatisfy { $0.label.count == 2 })
    XCTAssertEqual(labeled[0].label, "aa")
  }

  // MARK: Hierarchical labeling

  func testDenseMultiGroupLabelsShareGroupPrefix() {
    // 40 elements in 4 groups of 10 → prefix a/s/d/f + suffix a…j
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    XCTAssertEqual(labeled.count, 40)

    let byGroup = Dictionary(grouping: labeled, by: { $0.element.groupingAncestor })
    XCTAssertEqual(byGroup.count, 4)
    for (_, members) in byGroup {
      let prefixes = Set(members.map { String($0.label.prefix(1)) })
      XCTAssertEqual(prefixes.count, 1, "All members of a group share a prefix")
    }
    // First group (topmost) gets the home-row 'a' prefix
    let firstGroup = byGroup[.walkNode(0)] ?? []
    XCTAssertTrue(firstGroup.allSatisfy { $0.label.hasPrefix("a") })
  }

  func testNoLabelIsPrefixOfAnother() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    let labels = labeled.map(\.label)
    for label in labels {
      let collisions = labels.filter { $0 != label && $0.hasPrefix(label) }
      XCTAssertTrue(collisions.isEmpty, "'\(label)' is a prefix of \(collisions)")
    }
  }

  func testAllLabelsUnique() {
    let labeled = LabelGenerator.label(makeElements(count: 200, groups: 8))
    XCTAssertEqual(Set(labeled.map(\.label)).count, 200)
  }

  func testUnevenGroupsKeepPrefixSafety() {
    // One big group (40 → 2-char suffixes) + four small (5 → 1-char suffixes).
    // Mixed total lengths must still never produce prefix collisions.
    var elements: [DiscoveredElement] = []
    for i in 0..<60 {
      let group = i < 40 ? 0 : (i - 40) % 4 + 1
      elements.append(element(groupingAncestor: .walkNode(group), x: CGFloat(i) * 20))
    }
    let labeled = LabelGenerator.label(elements)
    let labels = labeled.map(\.label)
    XCTAssertEqual(Set(labels).count, labels.count)
    for label in labels {
      let collisions = labels.filter { $0 != label && $0.hasPrefix(label) }
      XCTAssertTrue(collisions.isEmpty, "'\(label)' is a prefix of \(collisions)")
    }
  }

  func testFilterNarrowsToGroup() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    // Group 0 has prefix 'a' — 10 members
    let filtered = LabelGenerator.filter(labeled, prefix: "a")
    XCTAssertEqual(filtered.count, 10)
    XCTAssertTrue(filtered.allSatisfy { $0.label.hasPrefix("a") })
  }

  func testExactMatchStillWorks() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    let first = labeled[0]
    XCTAssertNotNil(LabelGenerator.exactMatch(in: labeled, for: first.label))
    XCTAssertNil(LabelGenerator.exactMatch(in: labeled, for: first.label + "a"))
  }
}
