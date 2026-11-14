import AppKit

// MARK: - Scan mode

enum ScanMode {
  case interactive
  case scrollable
}

// MARK: - Pipeline context & state

/// Immutable inputs shared by every pass in one scan.
struct DiscoveryContext {
  let app: AXElement
  let window: AXElement
  let windowFrame: CGRect?
  let primaryScreenHeight: CGFloat
  let screens: [NSScreen]
  let mode: ScanMode
  let roles: Set<String>
  let isCancelled: () -> Bool
}

/// Mutable state accumulated as passes run.
final class DiscoveryState {
  var results: [DiscoveredElement] = []
  var roleCount: [String: Int] = [:]

  /// Frames (NSScreen coords) of opaque provider groups seen during tree walks —
  /// regions whose content is hidden from traversal (e.g. Safari's Start Page).
  var opaqueRegions: [CGRect] = []

  var sawWebArea: Bool { roleCount[AXRoleName.webArea] != nil }
}

// MARK: - Pass protocol

/// One discovery strategy. The pipeline runs each pass in order; a pass declares
/// whether the current state warrants running it. New app quirks become new passes,
/// not edits to existing ones.
protocol DiscoveryPass {
  var name: String { get }
  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool
  func run(state: DiscoveryState, context: DiscoveryContext)
}

// MARK: - Shared tree walker

/// Recursive AX tree traversal shared by the tree-walk and fallback passes.
struct ElementTreeWalker {
  static let maxDepth = 25
  static let maxElements = 500

  func walk(from root: AXElement, state: DiscoveryState, context: DiscoveryContext) {
    visit(root, depth: 0, state: state, context: context)
  }

  private func visit(_ element: AXElement, depth: Int, state: DiscoveryState, context: DiscoveryContext) {
    guard !context.isCancelled(), depth <= Self.maxDepth,
          state.results.count < Self.maxElements else { return }
    guard !element.isHidden, element.isEnabled else { return }

    let role = element.role
    if let role {
      state.roleCount[role, default: 0] += 1
      let matched = context.roles.contains(role)
        || (context.mode == .interactive && element.supportsPress)
      if matched,
         let frame = element.frame(primaryScreenHeight: context.primaryScreenHeight),
         frame.width >= 4, frame.height >= 4,
         context.windowFrame.map({ $0.intersects(frame) }) ?? true,
         let screen = context.screens.first(where: { $0.frame.intersects(frame) }) {
        state.results.append(DiscoveredElement(element: element, screenFrame: frame, role: role, screen: screen))
      }
    }

    if role == AXRoleName.opaqueProviderGroup,
       let frame = element.frame(primaryScreenHeight: context.primaryScreenHeight) {
      state.opaqueRegions.append(frame)
    }

    for child in element.children {
      guard state.results.count < Self.maxElements else { break }
      visit(child, depth: depth + 1, state: state, context: context)
    }
  }
}
