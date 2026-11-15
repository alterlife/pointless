import AppKit
import OSLog

final class ElementDiscovery {
  static let interactiveRoles: Set<String> = [
    AXRoleName.button, AXRoleName.link, AXRoleName.textField, AXRoleName.textArea,
    AXRoleName.checkBox, AXRoleName.radioButton, AXRoleName.popUpButton, AXRoleName.menuItem,
    AXRoleName.comboBox, AXRoleName.tabGroup, AXRoleName.disclosureTriangle,
    AXRoleName.incrementor, AXRoleName.slider
  ]

  // Browsers expose no AXScrollArea — AXWebArea is the scroll container.
  static let scrollableRoles: Set<String> = [AXRoleName.scrollArea, AXRoleName.webArea]

  // WebKit/Chromium build the AX tree lazily once assistive access is enabled.
  private static let assistiveAccessSettleMicroseconds: UInt32 = 300_000

  private let passes: [DiscoveryPass] = [
    TreeWalkPass(),
    PressFallbackPass(),
    FocusedElementFallbackPass(),
    HitTestPass(),
    OcclusionPass()
  ]

  private var cancelled = false

  func cancel() {
    cancelled = true
  }

  func scan(
    mode: ScanMode = .interactive,
    onProgress: (@MainActor ([NavigationTarget]) -> Void)? = nil,
    completion: @escaping @MainActor ([NavigationTarget]) -> Void
  ) {
    cancelled = false
    // NSScreen is main-thread-only — capture screens before hopping to the scan queue.
    let screens = NSScreen.screens
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        Task { @MainActor in completion([]) }
        return
      }
      let elements = self.performScan(mode: mode, screens: screens, onProgress: onProgress)
      Task { @MainActor in completion(elements) }
    }
  }

  private func performScan(
    mode: ScanMode, screens: [NSScreen],
    onProgress: (@MainActor ([NavigationTarget]) -> Void)?
  ) -> [NavigationTarget] {
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

    let scanStart = Date()
    let state = DiscoveryState()
    for pass in passes where !cancelled && pass.shouldRun(state: state, context: context) {
      let passStart = Date()
      let before = state.results.count
      pass.run(state: state, context: context)
      Logger.debug(
        "Discovery pass \(pass.name): +\(state.results.count - before) elements " +
        "in \(Int(Date().timeIntervalSince(passStart) * 1000))ms",
        logger: Logger.pluginLifecycle
      )
      if let onProgress {
        let snapshot = Self.deduplicateAndRegroup(state.results, mode: mode)
        Task { @MainActor in onProgress(snapshot) }
      }
    }
    Logger.debug("Discovery scan took \(Int(Date().timeIntervalSince(scanStart) * 1000))ms",
                 logger: Logger.pluginLifecycle)

    let unique = Self.deduplicateAndRegroup(state.results, mode: mode)

    Logger.debug(
      "Discovery: \(unique.count) elements, \(state.visitedCount) visited, " +
      "roles=\(state.roleCount.sorted { $0.value > $1.value }.prefix(15))",
      logger: Logger.pluginLifecycle
    )
    return unique
  }

  static func deduplicateAndRegroup(
    _ results: [NavigationTarget], mode: ScanMode
  ) -> [NavigationTarget] {
    var seen = Set<String>()
    var unique = results.filter { seen.insert($0.dedupKey).inserted }
    for index in unique.indices where unique[index].text.isEmpty {
      unique[index].text = unique[index].node?.firstTextDescendant ?? ""
    }

    // Scroll areas sharing a corner still scroll different content — keep them all.
    if mode == .interactive {
      let beforeCollapse = unique.count
      unique = unique.mergeSharedAnchors()
      unique = unique.dropContainedPassiveElements()
      unique = unique.dropRedundantContainers()
      if unique.count < beforeCollapse {
        Logger.debug("Discovery: dropped \(beforeCollapse - unique.count) redundant elements",
                     logger: Logger.pluginLifecycle)
      }
    }

    return unique.regroupedForLabels()
  }
}
