import AppKit

/// An interactive (or scrollable) on-screen element found by a discovery pass.
struct DiscoveredElement {
  let element: AXElement
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen

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
}
