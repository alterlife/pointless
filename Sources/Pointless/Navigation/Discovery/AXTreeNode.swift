import AppKit

final class AXTreeNode {
  let id: Int
  let element: AXElement
  private(set) weak var parent: AXTreeNode?
  private(set) var children: [AXTreeNode] = []

  init(id: Int, element: AXElement, parent: AXTreeNode?) {
    self.id = id
    self.element = element
    self.parent = parent
  }

  func add(_ child: AXTreeNode) {
    children.append(child)
  }
}
