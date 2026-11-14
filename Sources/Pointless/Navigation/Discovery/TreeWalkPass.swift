import AppKit

/// Primary discovery: walk the AX tree from the focused window.
struct TreeWalkPass: DiscoveryPass {
  let name = "tree-walk"

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool { true }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    ElementTreeWalker().walk(from: context.window, state: state, context: context)
  }
}
