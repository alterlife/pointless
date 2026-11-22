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
    let screens = NSScreen.screens
    let cursorLocation = NSEvent.mouseLocation
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        Task { @MainActor in completion([]) }
        return
      }
      let elements = self.performScan(
        mode: mode, screens: screens, cursorLocation: cursorLocation, onProgress: onProgress
      )
      Task { @MainActor in completion(elements) }
    }
  }

  private func performScan(
    mode: ScanMode, screens: [NSScreen], cursorLocation: CGPoint,
    onProgress: (@MainActor ([NavigationTarget]) -> Void)?
  ) -> [NavigationTarget] {
    let primaryHeight = screens.first?.frame.height ?? 0
    let cocoaPoint = cursorLocation
    let quartzPoint = CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)
    guard let app = Self.targetApplication(
      cocoaPoint: cocoaPoint, quartzPoint: quartzPoint, primaryScreenHeight: primaryHeight
    ) else { return [] }
    if app.enableAssistiveAccess() {
      Logger.debug("Discovery: enabled assistive access, waiting for AX tree",
                   logger: Logger.pluginLifecycle)
      usleep(Self.assistiveAccessSettleMicroseconds)
    }
    guard let window = Self.scanRoot(for: app) else { return [] }

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
      if let onProgress, pass.name != "occlusion" {
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

  private static func targetApplication(
    cocoaPoint: CGPoint, quartzPoint: CGPoint, primaryScreenHeight: CGFloat
  ) -> AXElement? {
    if let front = AXElement.frontmostApplication(),
       let focused = front.focusedWindow,
       let frame = focused.frame(primaryScreenHeight: primaryScreenHeight),
       frame.contains(cocoaPoint) {
      return front
    }
    if let pid = windowOwnerPID(at: quartzPoint) {
      return AXElement.application(pid: pid)
    }
    return AXElement.frontmostApplication()
  }

  private static func windowOwnerPID(at quartzPoint: CGPoint, ignoringPID: pid_t = getpid()) -> pid_t? {
    guard let list = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return nil }
    for info in list {
      guard let owner = info[kCGWindowOwnerPID as String] as? Int,
            owner != Int(ignoringPID),
            let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
            let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            bounds.contains(quartzPoint)
      else { continue }
      return pid_t(owner)
    }
    return nil
  }

  private static func scanRoot(for app: AXElement) -> (any AXNode)? {
    app.focusedWindow ?? app.windows.first ?? app
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
