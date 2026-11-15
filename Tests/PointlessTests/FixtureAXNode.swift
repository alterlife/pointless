import AppKit
@testable import PointlessCore

/// In-memory AXNode for replaying discovery scenarios without live AX calls.
/// Frames are NSScreen coords, matching what NodeAttributes carries.
final class FixtureAXNode: AXNode {
  let role: String?
  var children: [any AXNode] = []
  var parent: (any AXNode)?
  var frame: CGRect?
  var isHidden = false
  var isEnabled = true
  private var _supportsPress = false
  private(set) var pressCheckCount = 0
  var hitTest: ((CGFloat, CGFloat) -> (any AXNode)?)?
  var focusedWindow: (any AXNode)?
  var focusedUIElement: (any AXNode)?
  var hasScrollIndicators = false
  var pressResult = true
  var axIdentity: UInt { UInt(bitPattern: ObjectIdentifier(self)) }

  var supportsPress: Bool {
    get {
      pressCheckCount += 1
      return _supportsPress
    }
    set { _supportsPress = newValue }
  }

  init(role: String? = nil, frame: CGRect? = nil) {
    self.role = role
    self.frame = frame
  }

  @discardableResult
  func add(_ child: FixtureAXNode) -> FixtureAXNode {
    children.append(child)
    child.parent = self
    return child
  }

  func nodeAttributes(primaryScreenHeight: CGFloat) -> NodeAttributes {
    NodeAttributes(
      children: children, role: role, isHidden: isHidden,
      isEnabled: isEnabled, frame: frame
    )
  }

  func frame(primaryScreenHeight: CGFloat) -> CGRect? { frame }

  func elementAt(axX: CGFloat, axY: CGFloat) -> (any AXNode)? {
    hitTest?(axX, axY)
  }

  func isSameElement(as other: any AXNode) -> Bool {
    axIdentity == other.axIdentity
  }

  func isDescendant(of ancestor: any AXNode, maxHops: Int) -> Bool {
    var current = parent
    for _ in 0..<maxHops {
      guard let node = current else { return false }
      if node.isSameElement(as: ancestor) { return true }
      current = node.parent
    }
    return false
  }

  func performPress() -> Bool { pressResult }

  func enableAssistiveAccess() -> Bool { false }
}
