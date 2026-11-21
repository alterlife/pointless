import AppKit
import OSLog

/// Fallback for apps whose window containers expose empty AXChildren (Firefox, Mullvad):
/// the focused-element API still reaches the full tree, so walk up from the focused
/// element to a content root and traverse from there.
struct FocusedElementFallbackPass: DiscoveryPass {
  let name = "focused-element-fallback"

  static let resultThreshold = 5
  private static let maxParentWalk = ElementTreeWalker.maxDepth

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool {
    state.results.count < Self.resultThreshold
  }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    guard let root = contentRoot(from: context.app) else { return }
    Logger.debug("Discovery fallback: window walk had \(state.results.count) hits, root=\(root.role ?? "?")",
                 logger: Logger.pluginLifecycle)
    ElementTreeWalker().walk(from: root, state: state, context: context)
  }

  private func contentRoot(from app: any AXNode) -> (any AXNode)? {
    guard var current = app.focusedUIElement else { return nil }

    var topWebArea: (any AXNode)?
    var topScrollArea: (any AXNode)?
    var topBrowser: (any AXNode)?

    for _ in 0..<Self.maxParentWalk {
      guard let role = current.role,
            role != AXRoleName.application, role != AXRoleName.window else { break }
      switch role {
      case AXRoleName.webArea:
        topWebArea = current
      case AXRoleName.scrollArea:
        topScrollArea = current
      case AXRoleName.browser:
        topBrowser = current
      default:
        break
      }
      guard let parent = current.parent else { break }
      current = parent
    }

    return topWebArea ?? topScrollArea ?? topBrowser ?? (current.children.isEmpty ? nil : current)
  }
}
