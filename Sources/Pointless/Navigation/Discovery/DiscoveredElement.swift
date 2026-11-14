import AppKit

/// Identity of the ancestor an element groups under for labeling — same value
/// means shared label prefix. Not necessarily the direct AX parent: walk elements
/// reference traversal node ids climbed to the nearest ancestor with multiple
/// discoveries; hit-test elements reference their AXParent hash.
enum GroupingAncestor: Hashable {
  /// Traversal node id — indexes DiscoveryState.nodeParent/subtreeCount.
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
}
