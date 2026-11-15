import AppKit

final class AXTreeNode {
  let id: Int
  let element: any AXNode
  private(set) weak var parent: AXTreeNode?
  private(set) var children: [AXTreeNode] = []

  init(id: Int, element: any AXNode, parent: AXTreeNode?) {
    self.id = id
    self.element = element
    self.parent = parent
  }

  func add(_ child: AXTreeNode) {
    children.append(child)
  }
}
