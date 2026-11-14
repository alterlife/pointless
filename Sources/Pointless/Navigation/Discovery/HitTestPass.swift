import AppKit
import OSLog

/// Safari's Start Page hides its content from traversal entirely (an opaque provider
/// is present but no AXWebArea ever appears). Position hit-testing still resolves the
/// hidden elements — grid-probe the window; dedup skips the chrome already found.
struct HitTestPass: DiscoveryPass {
  let name = "hit-test"

  /// Grid spacing — small enough to land on every favorites-sized tile,
  /// large enough to keep the probe count bounded.
  private static let step: CGFloat = 44
  private static let maxProbes = 1200

  /// Max AXParent hops when climbing from a deep hit to its clickable ancestor.
  private static let maxAncestorClimb = 5

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool {
    context.mode == .interactive && !state.sawWebArea && !state.opaqueRegions.isEmpty
  }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    guard let region = context.windowFrame else { return }
    var seen = Set(state.results.map(\.dedupKey))
    var probes = 0
    var nsY = region.minY + Self.step / 2
    while nsY < region.maxY {
      var nsX = region.minX + Self.step / 2
      while nsX < region.maxX {
        guard !context.isCancelled(), probes < Self.maxProbes,
              state.results.count < ElementTreeWalker.maxElements else { return }
        probes += 1
        let probeX = nsX
        nsX += Self.step
        // AX hit-testing uses top-left-origin coordinates
        guard let hit = context.app.elementAt(axX: probeX, axY: context.primaryScreenHeight - nsY),
              let target = clickableAncestor(of: hit, roles: context.roles),
              let role = target.role,
              let frame = target.frame(primaryScreenHeight: context.primaryScreenHeight),
              frame.width >= 4, frame.height >= 4,
              let screen = context.screens.first(where: { $0.frame.intersects(frame) })
        else { continue }
        let parent = target.parent
        let element = DiscoveredElement(
          element: target, screenFrame: frame, role: role, screen: screen,
          groupingAncestor: .hitTestParent(CFHash(parent?.raw ?? target.raw))
        )
        guard seen.insert(element.dedupKey).inserted else { continue }
        state.results.append(element)
      }
      nsY += Self.step
    }
  }

  /// Climb from a hit-test result (often a deep AXImage/AXStaticText) to the nearest
  /// ancestor that is actually clickable.
  private func clickableAncestor(of element: AXElement, roles: Set<String>) -> AXElement? {
    var current = element
    for _ in 0..<Self.maxAncestorClimb {
      if let role = current.role, roles.contains(role) || current.supportsPress {
        return current
      }
      guard let parent = current.parent else { return nil }
      current = parent
    }
    return nil
  }
}
