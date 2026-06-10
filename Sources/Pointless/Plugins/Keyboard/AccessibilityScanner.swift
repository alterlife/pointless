import AppKit
import ApplicationServices
import OSLog

struct DiscoveredElement {
  let element: AXUIElement
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen
}

extension Array where Element == DiscoveredElement {
  /// Sort top-to-bottom (highest Y first in NSScreen coords), left-to-right within each row.
  func sortedByPosition() -> [DiscoveredElement] {
    sorted { lhs, rhs in
      if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
      return lhs.screenFrame.minX < rhs.screenFrame.minX
    }
  }
}

/// Converts AX top-left-origin coordinates to NSScreen bottom-left-origin
internal func axToNSScreen(axOrigin: CGPoint, axSize: CGSize, primaryScreenHeight: CGFloat) -> CGRect {
  let nsScreenY = primaryScreenHeight - axOrigin.y - axSize.height
  return CGRect(x: axOrigin.x, y: nsScreenY, width: axSize.width, height: axSize.height)
}

// MARK: - AX string constants (raw values, avoids dependency on kAXXXX constants)

private enum AXRole {
  static let button = "AXButton"
  static let link = "AXLink"
  static let textField = "AXTextField"
  static let textArea = "AXTextArea"
  static let checkBox = "AXCheckBox"
  static let radioButton = "AXRadioButton"
  static let popUpButton = "AXPopUpButton"
  static let menuItem = "AXMenuItem"
  static let comboBox = "AXComboBox"
  static let tabGroup = "AXTabGroup"
  static let disclosureTriangle = "AXDisclosureTriangle"
  static let incrementor = "AXIncrementor"
  static let slider = "AXSlider"
  static let scrollArea = "AXScrollArea"
}

private enum AXAttr {
  static let role = "AXRole"
  static let enabled = "AXEnabled"
  static let hidden = "AXHidden"
  static let position = "AXPosition"
  static let size = "AXSize"
  static let focusedWindow = "AXFocusedWindow"
  static let mainWindow = "AXMainWindow"
  static let children = "AXChildren"
}

// MARK: - Scanner

final class AccessibilityScanner {
  enum ScanMode { case interactive, scrollable }

  private static let interactiveRoles: Set<String> = [
    AXRole.button, AXRole.link, AXRole.textField, AXRole.textArea,
    AXRole.checkBox, AXRole.radioButton, AXRole.popUpButton, AXRole.menuItem,
    AXRole.comboBox, AXRole.tabGroup, AXRole.disclosureTriangle,
    AXRole.incrementor, AXRole.slider
  ]

  private static let scrollableRoles: Set<String> = [AXRole.scrollArea]

  private static let maxDepth = 25
  private static let maxElements = 500

  /// If the window scan yields fewer results than this, retry via AXFocusedUIElement.
  /// Firefox/Mullvad expose empty AXChildren on window containers, so the fallback
  /// walks from the focused element up to a content root instead.
  private static let fallbackThreshold = 5

  /// Max AXParent hops when walking up to find a content root.
  private static let maxParentWalk = 30

  private var isCancelled = false

  /// Frames (NSScreen coords) of childless AXOpaqueProviderGroups found during traversal
  private var opaqueRegions: [CGRect] = []

  /// Grid spacing for opaque-region hit-testing — small enough to land on every
  /// favorites-sized tile, large enough to keep the probe count bounded.
  private static let hitTestStep: CGFloat = 44
  private static let maxHitTests = 1200

  func cancel() {
    isCancelled = true
  }

  func scan(mode: ScanMode = .interactive, completion: @escaping @MainActor ([DiscoveredElement]) -> Void) {
    isCancelled = false
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

  /// WebKit/Chromium only expose their full AX tree to assistive clients — without this,
  /// web content (Safari pages, Electron apps) is an AXOpaqueProviderGroup with no children.
  /// The tree is built lazily after enabling, so when we just turned it on, give the app
  /// a moment before traversing (we're on a background queue).
  private func enableAssistiveAccess(for axApp: AXUIElement) {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, &ref)
    let alreadyEnabled = (ref as? NSNumber)?.boolValue ?? false
    AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    if !alreadyEnabled {
      Logger.info("AX scan: enabled enhanced UI, waiting for AX tree", logger: Logger.pluginLifecycle)
      usleep(300_000)
    }
  }

  private func performScan(mode: ScanMode, screens: [NSScreen]) -> [DiscoveredElement] {
    guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableAssistiveAccess(for: axApp)
    guard let window = focusedWindow(from: axApp) else { return [] }
    let primaryHeight = screens.first?.frame.height ?? 0
    let windowFrame = axFrame(of: window, primaryHeight: primaryHeight)
    let roles: Set<String>
    switch mode {
    case .interactive: roles = Self.interactiveRoles
    case .scrollable: roles = Self.scrollableRoles
    }

    let context = TraversalContext(
      primaryHeight: primaryHeight, roles: roles, visibleRect: windowFrame, mode: mode, screens: screens
    )

    // Primary: traverse from the focused window
    var results: [DiscoveredElement] = []
    var roleCount: [String: Int] = [:]
    opaqueRegions = []
    traverse(window, depth: 0, results: &results, roleCount: &roleCount, context: context)

    // Safari's Start Page hides its content from traversal entirely (an opaque provider
    // is present but no AXWebArea ever appears). Position hit-testing still resolves the
    // hidden elements — grid-probe the whole window; dedup skips the chrome we already have.
    if mode == .interactive, roleCount["AXWebArea"] == nil, !opaqueRegions.isEmpty,
       let windowRegion = windowFrame, !isCancelled {
      let hits = hitTestScan(region: windowRegion, axApp: axApp, context: context, existing: results)
      Logger.debug("AX scan: window hit-test found \(hits.count) elements",
                   logger: Logger.pluginLifecycle)
      results.append(contentsOf: hits)
    }

    // Fallback: Firefox/Mullvad expose empty AXChildren on window containers but the
    // focused element API still reaches the full accessibility tree. Walk up from the
    // focused element to a content root and traverse from there.
    if results.count < Self.fallbackThreshold, let root = contentRoot(from: axApp) {
      Logger.info("AX scan: fallback — window had \(results.count) hits",
                  logger: Logger.pluginLifecycle)
      traverse(root, depth: 0, results: &results, roleCount: &roleCount, context: context)
      // The fallback tree can overlap the window tree — drop duplicate elements
      var seen = Set<String>()
      results = results.filter { seen.insert("\($0.role)|\($0.screenFrame)").inserted }
    }

    let total = roleCount.values.reduce(0, +)
    Logger.debug(
      "AX scan: \(results.count) matches, \(total) visited, " +
      "roles=\(roleCount.sorted { $0.value > $1.value }.prefix(15))",
      logger: Logger.pluginLifecycle
    )
    return results
  }

  /// Probe a screen region on a grid with AXUIElementCopyElementAtPosition, which pierces
  /// opaque provider boundaries, then climb from each hit to its clickable ancestor.
  private func hitTestScan(
    region: CGRect,
    axApp: AXUIElement,
    context: TraversalContext,
    existing: [DiscoveredElement]
  ) -> [DiscoveredElement] {
    var found: [DiscoveredElement] = []
    var seen = Set<String>(existing.map { "\($0.role)|\($0.screenFrame)" })
    var probes = 0
    var errors = 0
    var hitRoles: [String: Int] = [:]
    var nsY = region.minY + Self.hitTestStep / 2
    while nsY < region.maxY {
      var nsX = region.minX + Self.hitTestStep / 2
      while nsX < region.maxX {
        guard !isCancelled, probes < Self.maxHitTests, found.count < Self.maxElements else { break }
        probes += 1
        // AX hit-testing uses top-left-origin coordinates
        let axY = context.primaryHeight - nsY
        let probeX = nsX
        nsX += Self.hitTestStep
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(axApp, Float(probeX), Float(axY), &ref) == .success,
              let hit = ref else {
          errors += 1
          continue
        }
        hitRoles[axRole(of: hit) ?? "<no role>", default: 0] += 1
        guard let target = clickableAncestor(of: hit, roles: context.roles),
              let role = axRole(of: target),
              let frame = axFrame(of: target, primaryHeight: context.primaryHeight),
              frame.width >= 4, frame.height >= 4,
              seen.insert("\(role)|\(frame)").inserted,
              let screen = context.screens.first(where: { $0.frame.intersects(frame) })
        else { continue }
        found.append(DiscoveredElement(element: target, screenFrame: frame, role: role, screen: screen))
      }
      nsY += Self.hitTestStep
    }
    Logger.debug(
      "AX hit-test: \(probes) probes, \(errors) errors, " +
      "hit roles=\(hitRoles.sorted { $0.value > $1.value }.prefix(8))",
      logger: Logger.pluginLifecycle
    )
    return found
  }

  /// Climb from a hit-test result (often a deep AXImage/AXStaticText) to the nearest
  /// ancestor that is actually clickable.
  private func clickableAncestor(of element: AXUIElement, roles: Set<String>) -> AXUIElement? {
    var current = element
    for _ in 0..<5 {
      if let role = axRole(of: current), roles.contains(role) || hasPressAction(current) {
        return current
      }
      var ref: CFTypeRef?
      guard AXUIElementCopyAttributeValue(current, "AXParent" as CFString, &ref) == .success,
            let raw = ref else { return nil }
      current = unsafeBitCast(raw, to: AXUIElement.self)
    }
    return nil
  }

  /// Walk from AXFocusedUIElement up to a content root (AXWebArea, AXScrollArea) that
  /// can serve as a traversal starting point. Stops before AXApplication to avoid
  /// scanning the entire app (menu bars, other windows, etc.).
  private func contentRoot(from axApp: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      axApp, "AXFocusedUIElement" as CFString, &ref
    ) == .success, let raw = ref else { return nil }
    var current = unsafeBitCast(raw, to: AXUIElement.self)

    let contentRoles: Set<String> = ["AXWebArea", AXRole.scrollArea, "AXBrowser"]
    let stopRoles: Set<String> = ["AXApplication"]
    for _ in 0..<Self.maxParentWalk {
      if let role = axRole(of: current) {
        if contentRoles.contains(role) { return current }
        if stopRoles.contains(role) { break }
      }
      var parentRef: CFTypeRef?
      guard AXUIElementCopyAttributeValue(
        current, "AXParent" as CFString, &parentRef
      ) == .success, let parentRaw = parentRef else { break }
      current = unsafeBitCast(parentRaw, to: AXUIElement.self)
    }
    // Didn't find a content root — use the highest reachable ancestor that has children
    let arr = axChildren(of: current)
    // swiftlint:disable:next empty_count
    return arr.count > 0 ? current : nil
  }

  private func focusedWindow(from axApp: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, AXAttr.focusedWindow as CFString, &ref) == .success,
       let raw = ref {
      // AXUIElementCopyAttributeValue guarantees AXUIElement type for window attributes
      return unsafeBitCast(raw, to: AXUIElement.self)
    }
    if AXUIElementCopyAttributeValue(axApp, AXAttr.mainWindow as CFString, &ref) == .success,
       let raw = ref {
      return unsafeBitCast(raw, to: AXUIElement.self)
    }
    return nil
  }

  private struct TraversalContext {
    let primaryHeight: CGFloat
    let roles: Set<String>
    let visibleRect: CGRect?
    let mode: ScanMode
    let screens: [NSScreen]
  }

  private func traverse(
    _ element: AXUIElement,
    depth: Int,
    results: inout [DiscoveredElement],
    roleCount: inout [String: Int],
    context: TraversalContext
  ) {
    guard !isCancelled, depth <= Self.maxDepth, results.count < Self.maxElements else { return }
    guard !isHidden(element), isEnabled(element) else { return }

    let elementRole = axRole(of: element)
    if let role = elementRole {
      roleCount[role, default: 0] += 1
      let matched = context.roles.contains(role) || (context.mode == .interactive && hasPressAction(element))
      if matched,
         let frame = axFrame(of: element, primaryHeight: context.primaryHeight),
         frame.width >= 4, frame.height >= 4,
         context.visibleRect.map({ $0.intersects(frame) }) ?? true {
        if let screen = context.screens.first(where: { $0.frame.intersects(frame) }) {
          results.append(DiscoveredElement(element: element, screenFrame: frame, role: role, screen: screen))
        }
      }
    }

    let rawArr = axChildren(of: element)
    if elementRole == "AXOpaqueProviderGroup",
       let frame = axFrame(of: element, primaryHeight: context.primaryHeight) {
      opaqueRegions.append(frame)
    }

    // swiftlint:disable:next empty_count
    guard rawArr.count > 0 else { return }
    // CFArray of AXUIElement objects — map via unsafeBitCast to avoid CF conditional cast error
    let children = rawArr.map { unsafeBitCast($0 as AnyObject, to: AXUIElement.self) }

    for child in children {
      guard results.count < Self.maxElements else { break }
      traverse(child, depth: depth + 1, results: &results, roleCount: &roleCount, context: context)
    }
  }

  /// Try AXChildren first, then Firefox/Mullvad alternatives as fallbacks
  private static let childAttrs = [
    AXAttr.children, "AXChildrenInNavigationOrder", "AXVisibleChildren", "AXContents"
  ]

  private func axChildren(of element: AXUIElement) -> NSArray {
    for attr in Self.childAttrs {
      var ref: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
         let arr = ref as? NSArray, arr.count > 0 { // swiftlint:disable:this empty_count
        return arr
      }
    }
    return NSArray()
  }

  private func axRole(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, AXAttr.role as CFString, &ref) == .success else { return nil }
    return ref as? String
  }

  private func axBool(_ element: AXUIElement, attr: String, fallback: Bool) -> Bool {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return fallback }
    return (ref as? NSNumber)?.boolValue ?? fallback
  }

  private func isEnabled(_ element: AXUIElement) -> Bool { axBool(element, attr: AXAttr.enabled, fallback: true) }
  private func isHidden(_ element: AXUIElement) -> Bool { axBool(element, attr: AXAttr.hidden, fallback: false) }

  /// Whether the element supports the AXPress action (clickable regardless of role).
  /// Used to discover interactive elements that use non-standard roles (e.g. Safari start page favorites).
  private func hasPressAction(_ element: AXUIElement) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let actions = names as? [String] else { return false }
    return actions.contains("AXPress")
  }

  private func axFrame(of element: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
    var posRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, AXAttr.position as CFString, &posRef) == .success,
          let posRaw = posRef, CFGetTypeID(posRaw) == AXValueGetTypeID() else { return nil }
    // CFGetTypeID verified — AXValue cast is safe here
    // swiftlint:disable:next force_cast
    let posAX = posRaw as! AXValue
    var position = CGPoint.zero
    AXValueGetValue(posAX, .cgPoint, &position)

    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, AXAttr.size as CFString, &sizeRef) == .success,
          let sizeRaw = sizeRef, CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
    // CFGetTypeID verified — AXValue cast is safe here
    // swiftlint:disable:next force_cast
    let sizeAX = sizeRaw as! AXValue
    var size = CGSize.zero
    AXValueGetValue(sizeAX, .cgSize, &size)

    return axToNSScreen(axOrigin: position, axSize: size, primaryScreenHeight: primaryHeight)
  }
}
