import XCTest
@testable import PointlessCore
import ApplicationServices
import CoreGraphics

final class LabelGeneratorTests: XCTestCase {
  private func element(
    groupingAncestor: GroupingAncestor, x: CGFloat = 0, size: CGFloat = 10
  ) -> NavigationTarget {
    NavigationTarget(
      element: AXElement(raw: AXUIElementCreateApplication(getpid())),
      screenFrame: CGRect(x: x, y: 0, width: size, height: size),
      role: "AXButton",
      screen: NSScreen.screens[0],
      groupingAncestor: groupingAncestor,
      node: nil
    )
  }

  private func makeElements(count: Int, groups: Int, size: CGFloat = 10) -> [NavigationTarget] {
    (0..<count).map {
      element(groupingAncestor: .walkNode($0 % groups), x: CGFloat($0) * 20, size: size)
    }
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

  func testAdjacentLabelsDifferInFirstChar() {
    // 28 elements in one group → flat 2-char labels. Spatial neighbors
    // should get labels one keystroke apart (Vimium-style ordering).
    let labeled = LabelGenerator.label(makeElements(count: 28, groups: 1))
    for pair in zip(labeled, labeled.dropFirst()) {
      XCTAssertNotEqual(
        pair.0.label.first, pair.1.label.first,
        "\(pair.0.label) and \(pair.1.label) share a first char"
      )
    }
  }

  // MARK: Element-text labels

  private func textElement(_ text: String, x: CGFloat) -> NavigationTarget {
    var target = element(groupingAncestor: .walkNode(0), x: x)
    target.text = text
    return target
  }

  func testTextLabelsComeFromElementText() {
    let labeled = LabelGenerator.label(
      [textElement("Save", x: 0), textElement("Cancel", x: 20)],
      strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "s")
    XCTAssertEqual(labeled[1].label, "c")
  }

  func testTextLabelCollisionsScanSecondWord() {
    // First letters collide on "n" — later elements scan word-two letters.
    let labeled = LabelGenerator.label(
      [
        textElement("New Session", x: 0), textElement("New Settings", x: 20),
        textElement("New Song", x: 40)
      ],
      strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "ns")
    XCTAssertEqual(labeled[1].label, "ne")
    XCTAssertEqual(labeled[2].label, "no")
  }

  func testTextLabelPrefixConflictsFallBack() {
    // "sav" prefixes "sa" — the second Save can't extend into a conflict.
    let labeled = LabelGenerator.label(
      [textElement("Save", x: 0), textElement("Save", x: 20)],
      strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "sa")
    XCTAssertFalse(labeled[1].label.hasPrefix("sa"))
    XCTAssertEqual(Set(labeled.map(\.label)).count, 2)
  }

  func testShorterLabelBlocksLongerPrefix() {
    // "Ne" claims "n"; "Neuroport" can't take "ne"/"neu" — prefix ambiguity.
    let labeled = LabelGenerator.label(
      [textElement("Ne", x: 0), textElement("Neuroport", x: 20)],
      strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "ne")
    XCTAssertFalse(labeled[1].label.hasPrefix("ne"))
  }

  func testTextStrategyStaysFlatAboveGroupThreshold() {
    // 30 elements would normally go hierarchical — text strategy stays flat.
    let elements = (0..<30).map { textElement("Item \($0)", x: CGFloat($0) * 20) }
    let labeled = LabelGenerator.label(elements, strategy: .useClickableElementText)
    XCTAssertTrue(labeled.allSatisfy { !$0.label.contains("_") })
    XCTAssertEqual(labeled[0].label, "it")
  }

  func testShortTextGetsShortHint() {
    let labeled = LabelGenerator.label(
      [textElement("OK", x: 0)], strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "o")
  }

  func testEmptyTextFallsBackToKeys() {
    let labeled = LabelGenerator.label(
      [element(groupingAncestor: .walkNode(0), x: 0)],
      strategy: .useClickableElementText
    )
    XCTAssertEqual(labeled[0].label, "a")
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
    var elements: [NavigationTarget] = []
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

  func testNoLabelContainsBannedWord() {
    // 30 elements in the first group → 2-char suffixes where "ss" lands early,
    // which would spell "ass" under the "a" prefix without filtering.
    var elements: [NavigationTarget] = []
    for i in 0..<40 {
      elements.append(element(groupingAncestor: .walkNode(i < 30 ? 0 : 1), x: CGFloat(i) * 20))
    }
    let labeled = LabelGenerator.label(elements)

    XCTAssertEqual(labeled.count, 40)
    XCTAssertEqual(Set(labeled.map(\.label)).count, 40)
    for l in labeled {
      for word in BannedLabelWords.all {
        XCTAssertFalse(l.label.contains(word), "'\(l.label)' contains '\(word)'")
      }
    }
  }

  func testExactMatchStillWorks() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    let first = labeled[0]
    XCTAssertNotNil(LabelGenerator.exactMatch(in: labeled, for: first.label))
    XCTAssertNil(LabelGenerator.exactMatch(in: labeled, for: first.label + "a"))
  }

  // MARK: Collapsed groups

  func testDenseSmallGroupsCollapse() {
    // 40 small elements in 4 groups of 10 — every group is a dense cluster.
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    let collapsed = LabelGenerator.collapsedGroups(in: labeled)
    XCTAssertEqual(collapsed.count, 4)
    XCTAssertEqual(collapsed[0].label, "a_ (10 items)")
    XCTAssertEqual(collapsed[0].prefix, "a")
  }

  func testLargeMembersDoNotCollapse() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4, size: 100))
    XCTAssertTrue(LabelGenerator.collapsedGroups(in: labeled).isEmpty)
  }

  func testClusterBelowThresholdDoesNotCollapse() {
    // Group 0 has only 5 members — under the minimum; groups 1-3 are large.
    var elements: [NavigationTarget] = []
    for i in 0..<40 {
      let group = i < 5 ? 0 : (i - 5) % 3 + 1
      elements.append(
        element(groupingAncestor: .walkNode(group), x: CGFloat(i) * 20, size: group == 0 ? 10 : 100)
      )
    }
    let labeled = LabelGenerator.label(elements)
    XCTAssertTrue(LabelGenerator.collapsedGroups(in: labeled).isEmpty)
  }

  func testFlatLabelsNeverCollapse() {
    // 20 small elements in one group — flat labels have no shared prefix.
    let labeled = LabelGenerator.label(makeElements(count: 20, groups: 1))
    XCTAssertTrue(LabelGenerator.collapsedGroups(in: labeled).isEmpty)
  }

  func testCollapsedGroupFrameUnionsMembers() {
    let labeled = LabelGenerator.label(makeElements(count: 40, groups: 4))
    let collapsed = LabelGenerator.collapsedGroups(in: labeled)
    let firstGroup = collapsed.first { $0.prefix == "a" }!
    // Group 0 members sit at x = 0,80,160,... (i%4==0 → every 4th slot)
    XCTAssertEqual(firstGroup.frame.minX, 0, accuracy: 0.001)
    XCTAssertGreaterThan(firstGroup.frame.width, 200)
  }
}
