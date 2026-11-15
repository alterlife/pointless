import AppKit

// MARK: - Scan mode

enum ScanMode {
  case interactive
  case scrollable
}

// MARK: - Pipeline context & state

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

final class DiscoveryState {
  var results: [DiscoveredElement] = []
  var pressFallbackCandidates: [DiscoveredElement] = []
  var pressableCount = 0
  var visitedCount = 0
  var roleCount: [String: Int] = [:]

  var discoveredCount: Int { results.count + pressFallbackCandidates.count }
  var pressableRatio: Double {
    visitedCount > 0 ? Double(pressableCount) / Double(visitedCount) : 0
  }

  /// Frames (NSScreen coords) of opaque provider groups — regions the walk can't see inside.
  var opaqueRegions: [CGRect] = []

  private(set) var nextNodeID = 0
  var nodeParent: [Int: Int] = [:]

  func makeNodeID() -> Int {
    nextNodeID += 1
    return nextNodeID
  }

  var sawWebArea: Bool { roleCount[AXRoleName.webArea] != nil }
}

// MARK: - Pass protocol

protocol DiscoveryPass {
  var name: String { get }
  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool
  func run(state: DiscoveryState, context: DiscoveryContext)
}

// MARK: - Shared tree walker

struct ElementTreeWalker {
  // Chromium DOMs nest AXGroup chains 30+ deep — the cap must clear that.
  static let maxDepth = 100
  static let maxElements = 500

  func walk(from root: AXElement, state: DiscoveryState, context: DiscoveryContext) {
    visit(root, depth: 0, parentID: 0, state: state, context: context)
  }

  private func visit(
    _ element: AXElement, depth: Int, parentID: Int,
    state: DiscoveryState, context: DiscoveryContext
  ) {
    guard !context.isCancelled(), depth <= Self.maxDepth,
          state.discoveredCount < Self.maxElements else { return }
    guard !element.isHidden, element.isEnabled else { return }

    state.visitedCount += 1
    let pressable = context.mode == .interactive && element.supportsPress
    if pressable { state.pressableCount += 1 }

    let nodeID = state.makeNodeID()
    state.nodeParent[nodeID] = parentID

    let role = element.role
    if let role {
      state.roleCount[role, default: 0] += 1
      let roleMatched = context.roles.contains(role)
      if roleMatched || pressable,
         let frame = element.frame(primaryScreenHeight: context.primaryScreenHeight),
         frame.width >= 4, frame.height >= 4,
         context.windowFrame.map({ $0.intersects(frame) }) ?? true,
         let screen = context.screens.first(where: { $0.frame.intersects(frame) }) {
        let discovered = DiscoveredElement(
          element: element, screenFrame: frame, role: role, screen: screen,
          groupingAncestor: .walkNode(parentID), walkNodeID: nodeID
        )
        if roleMatched {
          state.results.append(discovered)
        } else {
          state.pressFallbackCandidates.append(discovered)
        }
      }
    }

    if role == AXRoleName.opaqueProviderGroup,
       let frame = element.frame(primaryScreenHeight: context.primaryScreenHeight) {
      state.opaqueRegions.append(frame)
    }

    for child in element.children {
      guard state.discoveredCount < Self.maxElements else { break }
      visit(child, depth: depth + 1, parentID: nodeID, state: state, context: context)
    }
  }
}
