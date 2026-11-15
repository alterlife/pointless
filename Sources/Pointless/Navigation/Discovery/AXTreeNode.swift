import AppKit

final class AXTreeNode {
  let id: Int
  let element: any AXNode
  let role: String?
  private(set) weak var parent: AXTreeNode?
  private(set) var children: [AXTreeNode] = []

  init(id: Int, element: any AXNode, parent: AXTreeNode?, role: String? = nil) {
    self.id = id
    self.element = element
    self.role = role
    self.parent = parent
  }

  func hasAncestor(role: String) -> Bool {
    var current = parent
    while let node = current {
      if node.role == role { return true }
      current = node.parent
    }
    return false
  }

  func add(_ child: AXTreeNode) {
    children.append(child)
  }
}
