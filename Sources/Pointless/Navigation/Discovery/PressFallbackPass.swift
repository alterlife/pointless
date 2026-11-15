import OSLog

/// Chromium marks genuinely clickable elements with AXPress; Gecko marks nearly
/// everything, so press-only discoveries are only trusted when the pressable
/// share of the visited UI stays low.
struct PressFallbackPass: DiscoveryPass {
  let name = "press-fallback"

  private static let maxPressableRatio = 0.5
  private static let minSampleForPressCheck = 30

  func shouldRun(state: DiscoveryState, context: DiscoveryContext) -> Bool {
    context.mode == .interactive && !state.pressFallbackCandidates.isEmpty
  }

  func run(state: DiscoveryState, context: DiscoveryContext) {
    let trustworthy = state.visitedCount < Self.minSampleForPressCheck
      || state.pressableRatio <= Self.maxPressableRatio
    if trustworthy {
      state.results.append(contentsOf: state.pressFallbackCandidates)
    } else {
      Logger.debug(
        "Discovery: skipped \(state.pressFallbackCandidates.count) press-fallback elements " +
        "(\(Int(state.pressableRatio * 100))% of UI is pressable)",
        logger: Logger.pluginLifecycle
      )
    }
    state.pressFallbackCandidates.removeAll()
  }
}
