import AppKit
import OSLog

/// Fallback for apps whose window containers expose empty AXChildren (Firefox, Mullvad):
/// the focused-element API still reaches the full tree, so walk up from the focused
/// element to a content root and traverse from there.
struct FocusedElementFallbackPass: DiscoveryPass {
  let name = "focused-element-fallback"

  /// If the tree walk yielded fewer results than this, the window tree is likely broken.
  static let resultThreshold = 5

  /// Max AXParent hops when walking up to find a content root.
  private static let maxParentWalk = 30

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool {
    state.results.count < Self.resultThreshold
  }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    guard let root = contentRoot(from: context.app) else { return }
    Logger.debug("Discovery fallback: window walk had \(state.results.count) hits",
                 logger: Logger.pluginLifecycle)
    ElementTreeWalker().walk(from: root, state: state, context: context)
  }

  /// Walk from the focused element up to a content root (AXWebArea, AXScrollArea) that
  /// can serve as a traversal starting point. Stops before AXApplication to avoid
  /// scanning the entire app (menu bars, other windows, etc.).
  private func contentRoot(from app: AXElement) -> AXElement? {
    guard var current = app.focusedUIElement else { return nil }

    let contentRoles: Set<String> = [AXRoleName.webArea, AXRoleName.scrollArea, AXRoleName.browser]
    for _ in 0..<Self.maxParentWalk {
      if let role = current.role {
        if contentRoles.contains(role) { return current }
        if role == AXRoleName.application { break }
      }
      guard let parent = current.parent else { break }
      current = parent
    }
    // Didn't find a content root — use the highest reachable ancestor that has children
    return current.children.isEmpty ? nil : current
  }
}
