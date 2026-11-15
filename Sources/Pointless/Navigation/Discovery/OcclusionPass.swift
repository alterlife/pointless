import AppKit
import OSLog

/// Drops elements hit-testing can no longer resolve. Visually-hidden controls
/// (e.g. Chromium `sr-only` skip links) keep an AX frame but paint nothing —
/// probes across the frame return whatever is actually on top instead.
struct OcclusionPass: DiscoveryPass {
  let name = "occlusion"

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool {
    context.mode == .interactive && !state.results.isEmpty
  }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    var kept: [NavigationTarget] = []
    var dropped = 0
    for element in state.results {
      if context.isCancelled() { break }
      if isReachable(element, context: context) {
        kept.append(element)
      } else {
        dropped += 1
      }
    }
    state.results = kept
    if dropped > 0 {
      Logger.debug("Discovery: dropped \(dropped) obscured elements", logger: Logger.pluginLifecycle)
    }
  }

  private func isReachable(_ discovered: NavigationTarget, context: DiscoveryContext) -> Bool {
    let frame = discovered.screenFrame
    let points = [
      CGPoint(x: frame.midX, y: frame.midY),
      CGPoint(x: frame.minX + frame.width * 0.25, y: frame.minY + frame.height * 0.25),
      CGPoint(x: frame.maxX - frame.width * 0.25, y: frame.minY + frame.height * 0.25),
      CGPoint(x: frame.minX + frame.width * 0.25, y: frame.maxY - frame.height * 0.25),
      CGPoint(x: frame.maxX - frame.width * 0.25, y: frame.maxY - frame.height * 0.25)
    ]
    return points.contains { point in
      guard let hit = context.app.elementAt(
        axX: point.x, axY: context.primaryScreenHeight - point.y
      ) else { return false }
      return hit.isSameElement(as: discovered.element)
        || hit.isDescendant(of: discovered.element, maxHops: 20)
    }
  }
}
