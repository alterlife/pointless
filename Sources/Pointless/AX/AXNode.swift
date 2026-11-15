import AppKit
import ApplicationServices

/// Anything the navigation pipeline can read — a live `AXUIElement` via
/// `AXElement`, or an in-memory fixture in tests.
protocol AXNode {
  var role: String? { get }
  var parent: (any AXNode)? { get }
  var children: [any AXNode] { get }
  var focusedWindow: (any AXNode)? { get }
  var focusedUIElement: (any AXNode)? { get }
  var supportsPress: Bool { get }
  var hasScrollIndicators: Bool { get }
  /// Stable identity for equality checks — CFHash for live elements.
  var axIdentity: UInt { get }

  func nodeAttributes(primaryScreenHeight: CGFloat) -> NodeAttributes
  func frame(primaryScreenHeight: CGFloat) -> CGRect?
  func elementAt(axX: CGFloat, axY: CGFloat) -> (any AXNode)?
  func isSameElement(as other: any AXNode) -> Bool
  func isDescendant(of ancestor: any AXNode, maxHops: Int) -> Bool
  func performPress() -> Bool
  func enableAssistiveAccess() -> Bool
}

extension AXNode {
  func isDescendant(of ancestor: any AXNode) -> Bool {
    isDescendant(of: ancestor, maxHops: 10)
  }
}
