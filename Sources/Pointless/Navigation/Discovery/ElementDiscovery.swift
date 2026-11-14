import AppKit
import OSLog

final class ElementDiscovery {
  private static let interactiveRoles: Set<String> = [
    AXRoleName.button, AXRoleName.link, AXRoleName.textField, AXRoleName.textArea,
    AXRoleName.checkBox, AXRoleName.radioButton, AXRoleName.popUpButton, AXRoleName.menuItem,
    AXRoleName.comboBox, AXRoleName.tabGroup, AXRoleName.disclosureTriangle,
    AXRoleName.incrementor, AXRoleName.slider
  ]

  // Browsers expose no AXScrollArea — AXWebArea is the scroll container.
  private static let scrollableRoles: Set<String> = [AXRoleName.scrollArea, AXRoleName.webArea]

  // WebKit/Chromium build the AX tree lazily once assistive access is enabled.
  private static let assistiveAccessSettleMicroseconds: UInt32 = 300_000

  private let passes: [DiscoveryPass] = [
    TreeWalkPass(),
    PressFallbackPass(),
    FocusedElementFallbackPass(),
    HitTestPass()
  ]

  private var cancelled = false

  func cancel() {
    cancelled = true
  }

  func scan(mode: ScanMode = .interactive, completion: @escaping @MainActor ([DiscoveredElement]) -> Void) {
    cancelled = false
    // NSScreen is main-thread-only — capture screens before hopping to the scan queue.
    let screens = NSScreen.screens
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        Task { @MainActor in completion([]) }
        return
      }
      let elements = self.performScan(mode: mode, screens: screens)
      Task { @MainActor in completion(elements) }
    }
  }

  private func performScan(mode: ScanMode, screens: [NSScreen]) -> [DiscoveredElement] {
    guard let app = AXElement.frontmostApplication() else { return [] }
    if app.enableAssistiveAccess() {
      Logger.debug("Discovery: enabled assistive access, waiting for AX tree",
                   logger: Logger.pluginLifecycle)
      usleep(Self.assistiveAccessSettleMicroseconds)
    }
    guard let window = app.focusedWindow else { return [] }

    let primaryHeight = screens.first?.frame.height ?? 0
    let context = DiscoveryContext(
      app: app,
      window: window,
      windowFrame: window.frame(primaryScreenHeight: primaryHeight),
      primaryScreenHeight: primaryHeight,
      screens: screens,
      mode: mode,
      roles: mode == .interactive ? Self.interactiveRoles : Self.scrollableRoles,
      isCancelled: { [weak self] in self?.cancelled ?? true }
    )

    let state = DiscoveryState()
    for pass in passes where !cancelled && pass.shouldRun(state: state, context: context) {
      let before = state.results.count
      pass.run(state: state, context: context)
      Logger.debug("Discovery pass \(pass.name): +\(state.results.count - before) elements",
                   logger: Logger.pluginLifecycle)
    }

    let unique = Self.deduplicateAndRegroup(state.results, mode: mode, nodeParent: state.nodeParent)

    Logger.debug(
      "Discovery: \(unique.count) elements, \(state.visitedCount) visited, " +
      "roles=\(state.roleCount.sorted { $0.value > $1.value }.prefix(15))",
      logger: Logger.pluginLifecycle
    )
    return unique
  }

  static func deduplicateAndRegroup(
    _ results: [DiscoveredElement], mode: ScanMode, nodeParent: [Int: Int]
  ) -> [DiscoveredElement] {
    var seen = Set<String>()
    var unique = results.filter { seen.insert($0.dedupKey).inserted }

    // Scroll areas sharing a corner still scroll different content — keep them all.
    if mode == .interactive {
      let beforeCollapse = unique.count
      unique = unique.mergeSharedAnchors()
      if unique.count < beforeCollapse {
        Logger.debug("Discovery: dropped \(beforeCollapse - unique.count) same-anchor elements",
                     logger: Logger.pluginLifecycle)
      }
    }

    return unique.regroupedForLabels(nodeParent: nodeParent)
  }
}
