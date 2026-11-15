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
  let element: any AXNode
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen
  /// The ancestor this element groups under — not necessarily its AX parent.
  var groupingAncestor: GroupingAncestor
  let node: AXTreeNode?
  /// Visible text (title/description/value) — feeds text-derived hints.
  var text: String = ""

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

  func dropContainedPassiveElements() -> [NavigationTarget] {
    let editableRoles: Set<String> = [AXRoleName.textField, AXRoleName.textArea]
    // Clicking these performs an action, so a contained field is redundant.
    // Plain containers (groups, tab panes) don't — the field stays editable.
    let activatingRoles: Set<String> = [
      AXRoleName.button, AXRoleName.link, AXRoleName.checkBox, AXRoleName.radioButton,
      AXRoleName.menuItem, AXRoleName.popUpButton, AXRoleName.comboBox
    ]
    let all = self
    return filter { inner in
      guard inner.role == AXRoleName.staticText || editableRoles.contains(inner.role)
      else { return true }
      let center = CGPoint(x: inner.screenFrame.midX, y: inner.screenFrame.midY)
      return !all.contains { outer in
        outer.dedupKey != inner.dedupKey
          && outer.screenFrame.contains(center)
          && outer.screenFrame.width * outer.screenFrame.height
            > inner.screenFrame.width * inner.screenFrame.height
          && (!editableRoles.contains(inner.role) || activatingRoles.contains(outer.role))
      }
    }
  }

  /// Press-fallback AXGroups that wrap a real control duplicate it —
  /// AXGroup is never an interactive role, so containment means wrapper.
  func dropRedundantContainers() -> [NavigationTarget] {
    let all = self
    return filter { outer in
      guard outer.role == AXRoleName.group else { return true }
      return !all.contains { inner in
        inner.dedupKey != outer.dedupKey
          && outer.screenFrame.contains(
            CGPoint(x: inner.screenFrame.midX, y: inner.screenFrame.midY)
          )
          && outer.screenFrame.width * outer.screenFrame.height
            > inner.screenFrame.width * inner.screenFrame.height
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
