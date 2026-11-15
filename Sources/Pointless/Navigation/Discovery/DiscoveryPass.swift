import AppKit

// MARK: - Scan mode

enum ScanMode {
  case interactive
  case scrollable
}

// MARK: - Pipeline context & state

struct DiscoveryContext {
  let app: any AXNode
  let window: any AXNode
  let windowFrame: CGRect?
  let primaryScreenHeight: CGFloat
  let screens: [NSScreen]
  let mode: ScanMode
  let roles: Set<String>
  let isCancelled: () -> Bool
}

final class DiscoveryState {
  var results: [NavigationTarget] = []
  var pressFallbackCandidates: [NavigationTarget] = []
  var pressableCount = 0
  var fallbackEligibleCount = 0
  var visitedCount = 0
  var roleCount: [String: Int] = [:]

  var discoveredCount: Int { results.count + pressFallbackCandidates.count }
  var pressableRatio: Double {
    fallbackEligibleCount > 0 ? Double(pressableCount) / Double(fallbackEligibleCount) : 0
  }

  /// Frames (NSScreen coords) of opaque provider groups — regions the walk can't see inside.
  var opaqueRegions: [CGRect] = []

  var roots: [AXTreeNode] = []

  private(set) var nextNodeID = 0

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

  func walk(from root: any AXNode, state: DiscoveryState, context: DiscoveryContext) {
    visit(root, parent: nil, depth: 0, state: state, context: context)
  }

  private func visit(
    _ element: any AXNode, parent: AXTreeNode?, depth: Int,
    state: DiscoveryState, context: DiscoveryContext
  ) {
    guard !context.isCancelled(), depth <= Self.maxDepth,
          state.discoveredCount < Self.maxElements else { return }

    let attrs = element.nodeAttributes(primaryScreenHeight: context.primaryScreenHeight)
    guard !attrs.isHidden, attrs.isEnabled else { return }

    if isOffscreenSubtree(attrs, context: context) { return }

    state.visitedCount += 1

    let node = AXTreeNode(id: state.makeNodeID(), element: element, parent: parent, role: attrs.role)
    if let parent {
      parent.add(node)
    } else {
      state.roots.append(node)
    }

    let roleMatched = isDiscoverableRole(attrs.role, node: node, context: context)
    let fallbackEligible = !roleMatched && isFallbackEligible(attrs, context: context)
    if fallbackEligible { state.fallbackEligibleCount += 1 }
    let pressable = fallbackEligible && element.supportsPress
    if pressable { state.pressableCount += 1 }

    recordDiscovery(node, attrs: attrs, pressable: pressable, state: state, context: context)

    if attrs.role == AXRoleName.opaqueProviderGroup, let frame = attrs.frame {
      state.opaqueRegions.append(frame)
    }

    for child in attrs.children {
      guard state.discoveredCount < Self.maxElements else { break }
      visit(child, parent: node, depth: depth + 1, state: state, context: context)
    }
  }

  /// Outline rows are click targets with no AXPress; scrollbar contents never are.
  private func isDiscoverableRole(_ role: String?, node: AXTreeNode, context: DiscoveryContext) -> Bool {
    guard let role, !node.hasAncestor(role: AXRoleName.scrollBar) else { return false }
    if context.roles.contains(role) { return true }
    return context.mode == .interactive
      && role == AXRoleName.row
      && node.hasAncestor(role: AXRoleName.outline)
  }

  private func isFallbackEligible(_ attrs: NodeAttributes, context: DiscoveryContext) -> Bool {
    guard context.mode == .interactive,
          let role = attrs.role, !context.roles.contains(role) else { return false }
    return targetFrame(attrs, context: context) != nil
  }

  private func recordDiscovery(
    _ node: AXTreeNode, attrs: NodeAttributes, pressable: Bool,
    state: DiscoveryState, context: DiscoveryContext
  ) {
    guard let role = attrs.role else { return }
    state.roleCount[role, default: 0] += 1
    let roleMatched = isDiscoverableRole(role, node: node, context: context)
    guard roleMatched || pressable,
          let (frame, screen) = targetFrame(attrs, context: context) else { return }
    let discovered = NavigationTarget(
      element: node.element, screenFrame: frame, role: role, screen: screen,
      groupingAncestor: .walkNode(node.parent?.id ?? 0), node: node
    )
    if roleMatched {
      state.results.append(discovered)
    } else {
      state.pressFallbackCandidates.append(discovered)
    }
  }

  private func targetFrame(_ attrs: NodeAttributes, context: DiscoveryContext) -> (CGRect, NSScreen)? {
    guard let frame = attrs.frame,
          frame.width >= 4, frame.height >= 4,
          context.windowFrame.map({ $0.intersects(frame) }) ?? true,
          let screen = context.screens.first(where: { $0.frame.intersects(frame) }) else { return nil }
    return (frame, screen)
  }

  private func isOffscreenSubtree(_ attrs: NodeAttributes, context: DiscoveryContext) -> Bool {
    guard let frame = attrs.frame, !attrs.children.isEmpty,
          frame.width > 0, frame.height > 0,
          let windowFrame = context.windowFrame else { return false }
    return !frame.intersects(windowFrame)
  }
}
