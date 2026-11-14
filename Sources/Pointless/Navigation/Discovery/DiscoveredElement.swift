import AppKit

/// Identity of the ancestor for labeling. same value = shared label prefix
/// Not necessarily the direct AX parent
enum GroupingAncestor: Hashable {
  /// Traversal node id - indexes DiscoveryState.nodeParent.
  case walkNode(Int)
  /// CFHash of the element's AXParent AXUIElement.
  case hitTestParent(UInt)
}

/// An interactive (or scrollable) on-screen element found by a discovery pass.
struct DiscoveredElement {
  let element: AXElement
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen
  /// The ancestor this element groups under — not necessarily its AX parent.
  let groupingAncestor: GroupingAncestor
  /// The element's own traversal node id — nil for elements found without a tree walk.
  var walkNodeID: Int?

  /// Identity for deduplication across passes — two discoveries of the same
  /// role at the same frame are the same control.
  var dedupKey: String { "\(role)|\(screenFrame)" }
}

extension Array where Element == DiscoveredElement {
  /// Sort top-to-bottom (highest Y first in NSScreen coords), left-to-right within each row.
  func sortedByPosition() -> [DiscoveredElement] {
    sorted { lhs, rhs in
      if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
      return lhs.screenFrame.minX < rhs.screenFrame.minX
    }
  }

  func mergeSharedAnchors(tolerance: CGFloat = 2) -> [DiscoveredElement] {
    reduce(into: [DiscoveredElement]()) { kept, element in
      if let index = kept.firstIndex(where: {
        abs($0.screenFrame.minX - element.screenFrame.minX) <= tolerance
          && abs($0.screenFrame.maxY - element.screenFrame.maxY) <= tolerance
      }) {
        if element.screenFrame.width * element.screenFrame.height
            < kept[index].screenFrame.width * kept[index].screenFrame.height {
          kept[index] = element
        }
      } else {
        kept.append(element)
      }
    }
  }

  /// Chromium wraps controls in single-child AXGroups — climb past ancestors
  /// holding only one surviving discovery so they don't get their own label prefix.
  func regroupedForLabels(nodeParent: [Int: Int]) -> [DiscoveredElement] {
    let counts = subtreeCounts(nodeParent: nodeParent)
    return map { element in
      guard case .walkNode(let groupID) = element.groupingAncestor else { return element }
      var current = groupID
      while counts[current] == 1, let parent = nodeParent[current], parent != 0 {
        current = parent
      }
      return DiscoveredElement(
        element: element.element, screenFrame: element.screenFrame, role: element.role,
        screen: element.screen, groupingAncestor: .walkNode(current), walkNodeID: element.walkNodeID
      )
    }
  }

  /// Discoveries in each walk node's subtree (inclusive), counting only these
  /// elements — dedup and anchor merging drop elements the walk already saw.
  private func subtreeCounts(nodeParent: [Int: Int]) -> [Int: Int] {
    var counts: [Int: Int] = [:]
    for element in self {
      var node = element.walkNodeID
      while let current = node, current != 0 {
        counts[current, default: 0] += 1
        node = nodeParent[current]
      }
    }
    return counts
  }
}
