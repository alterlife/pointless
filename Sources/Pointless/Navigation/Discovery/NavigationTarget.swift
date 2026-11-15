import AppKit

/// Ancestor identity for label grouping — equal values share a label prefix.
/// Not necessarily the direct AX parent.
enum GroupingAncestor: Hashable {
  /// Traversal node id.
  case walkNode(Int)
  /// CFHash of the element's AXParent AXUIElement.
  case hitTestParent(UInt)
}

/// An interactive (or scrollable) on-screen element found by a discovery pass.
struct NavigationTarget {
  let element: AXElement
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen
  /// The ancestor this element groups under — not necessarily its AX parent.
  var groupingAncestor: GroupingAncestor
  let node: AXTreeNode?

  var dedupKey: String { "\(role)|\(screenFrame)" }
}

extension Array where Element == NavigationTarget {
  /// Top-to-bottom in NSScreen coords (highest minY first), left-to-right.
  func sortedByPosition() -> [NavigationTarget] {
    sorted { lhs, rhs in
      if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
      return lhs.screenFrame.minX < rhs.screenFrame.minX
    }
  }

  func mergeSharedAnchors(tolerance: CGFloat = 2) -> [NavigationTarget] {
    reduce(into: [NavigationTarget]()) { kept, element in
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

  // Chromium wraps controls in single-child AXGroups — climb past ancestors
  // holding only one surviving discovery.
  func regroupedForLabels() -> [NavigationTarget] {
    let counts = subtreeCounts()
    return map { element in
      guard let group = element.node?.parent else { return element }
      var current = group
      while counts[current.id] == 1, let parent = current.parent {
        current = parent
      }
      var regrouped = element
      regrouped.groupingAncestor = .walkNode(current.id)
      return regrouped
    }
  }

  /// Post-dedup discovery counts per walked subtree.
  private func subtreeCounts() -> [Int: Int] {
    var counts: [Int: Int] = [:]
    for element in self {
      var node = element.node
      while let current = node {
        counts[current.id, default: 0] += 1
        node = current.parent
      }
    }
    return counts
  }
}
