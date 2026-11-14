import AppKit
import OSLog

final class ElementDiscovery {
  private static let interactiveRoles: Set<String> = [
    AXRoleName.button, AXRoleName.link, AXRoleName.textField, AXRoleName.textArea,
    AXRoleName.checkBox, AXRoleName.radioButton, AXRoleName.popUpButton, AXRoleName.menuItem,
    AXRoleName.comboBox, AXRoleName.tabGroup, AXRoleName.disclosureTriangle,
    AXRoleName.incrementor, AXRoleName.slider
  ]

  private static let scrollableRoles: Set<String> = [AXRoleName.scrollArea]

  /// How long to wait for WebKit/Chromium to build their AX tree after assistive
  /// access is first enabled (the tree is populated lazily).
  private static let assistiveAccessSettleMicroseconds: UInt32 = 300_000

  private let passes: [DiscoveryPass] = [
    TreeWalkPass(),
    FocusedElementFallbackPass(),
    HitTestPass()
  ]

  private var cancelled = false

  func cancel() {
    cancelled = true
  }

  func scan(mode: ScanMode = .interactive, completion: @escaping @MainActor ([DiscoveredElement]) -> Void) {
    cancelled = false
    // Capture screen info before leaving the main thread — NSScreen is AppKit API
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

    var seen = Set<String>()
    let unique = state.results.filter { seen.insert($0.dedupKey).inserted }

    let visited = state.roleCount.values.reduce(0, +)
    Logger.debug(
      "Discovery: \(unique.count) elements, \(visited) visited, " +
      "roles=\(state.roleCount.sorted { $0.value > $1.value }.prefix(15))",
      logger: Logger.pluginLifecycle
    )
    return unique
  }
}
