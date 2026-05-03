import AppKit
import ApplicationServices
import OSLog

struct DiscoveredElement {
  let element: AXUIElement
  let screenFrame: CGRect   // NSScreen coords (bottom-left origin)
  let role: String
  let screen: NSScreen
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

  private var isCancelled = false

  func cancel() {
    isCancelled = true
  }

  func scan(mode: ScanMode = .interactive, completion: @escaping @MainActor ([DiscoveredElement]) -> Void) {
    isCancelled = false
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        Task { @MainActor in completion([]) }
        return
      }
      let elements = self.performScan(mode: mode)
      Task { @MainActor in completion(elements) }
    }
  }

  private func performScan(mode: ScanMode) -> [DiscoveredElement] {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      Logger.info("AX scan: no frontmost app", logger: Logger.pluginLifecycle)
      return []
    }
    Logger.info("AX scan: app=\(app.localizedName ?? "?"), pid=\(app.processIdentifier)",
                logger: Logger.pluginLifecycle)
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = focusedWindow(from: axApp) else {
      Logger.info("AX scan: no focused/main window", logger: Logger.pluginLifecycle)
      return []
    }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let windowFrame = axFrame(of: window, primaryHeight: primaryHeight)
    Logger.info("AX scan: windowFrame=\(windowFrame.debugDescription)", logger: Logger.pluginLifecycle)
    let roles: Set<String>
    switch mode {
    case .interactive: roles = Self.interactiveRoles
    case .scrollable: roles = Self.scrollableRoles
    }

    // Primary: traverse from window
    var results: [DiscoveredElement] = []
    var stats = TraversalStats()
    traverse(window, depth: 0, results: &results, primaryHeight: primaryHeight,
             roles: roles, visibleRect: windowFrame, stats: &stats)

    // Fallback: if window traversal found very few results, try from focused element
    // (Firefox/Mullvad may expose empty AXChildren on containers but still have a focused element)
    if results.count < 5, let root = contentRoot(from: axApp) {
      let rootRole = axRole(of: root) ?? "?"
      Logger.info("AX scan: fallback from focused element, root role=\(rootRole)",
                  logger: Logger.pluginLifecycle)
      var fallbackStats = TraversalStats()
      traverse(root, depth: 0, results: &results, primaryHeight: primaryHeight,
               roles: roles, visibleRect: windowFrame, stats: &fallbackStats)
      stats.visited += fallbackStats.visited
      stats.maxDepthReached = max(stats.maxDepthReached, fallbackStats.maxDepthReached)
      stats.depthCutoffs += fallbackStats.depthCutoffs
      stats.elementCutoffs += fallbackStats.elementCutoffs
      stats.hiddenSkips += fallbackStats.hiddenSkips
      stats.noChildrenLeaves += fallbackStats.noChildrenLeaves
      for (k, v) in fallbackStats.roleCounts { stats.roleCounts[k, default: 0] += v }
    }

    Logger.info(
      "AX scan done: \(results.count) matches, \(stats.visited) visited, " +
      "maxDepth=\(stats.maxDepthReached), " +
      "depthCutoff=\(stats.depthCutoffs), elementCutoff=\(stats.elementCutoffs), " +
      "hiddenSkips=\(stats.hiddenSkips), noChildrenLeaves=\(stats.noChildrenLeaves), " +
      "roles=\(stats.roleCounts.sorted { $0.value > $1.value }.prefix(10))",
      logger: Logger.pluginLifecycle
    )
    return results
  }

  /// Walk from AXFocusedUIElement up to find a content root (AXWebArea, AXScrollArea, or AXGroup
  /// with children), then return it as a traversal starting point.
  private func contentRoot(from axApp: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      axApp, "AXFocusedUIElement" as CFString, &ref
    ) == .success, let raw = ref else {
      Logger.info("AX scan: no AXFocusedUIElement", logger: Logger.pluginLifecycle)
      return nil
    }
    var current = unsafeBitCast(raw, to: AXUIElement.self)
    let focusedRole = axRole(of: current) ?? "?"
    Logger.info("AX scan: focused element role=\(focusedRole)", logger: Logger.pluginLifecycle)

    // Walk up to find the best root (AXWebArea or AXScrollArea)
    let contentRoles: Set<String> = ["AXWebArea", AXRole.scrollArea, "AXBrowser"]
    for _ in 0..<30 {
      if let role = axRole(of: current), contentRoles.contains(role) {
        return current
      }
      var parentRef: CFTypeRef?
      guard AXUIElementCopyAttributeValue(
        current, "AXParent" as CFString, &parentRef
      ) == .success, let parentRaw = parentRef else { break }
      current = unsafeBitCast(parentRaw, to: AXUIElement.self)
    }
    // If we didn't find a content root, return whatever we have if it has children
    let arr = axChildren(of: current)
    return arr.count > 0 ? current : nil
  }

  private struct TraversalStats {
    var visited = 0
    var maxDepthReached = 0
    var depthCutoffs = 0
    var elementCutoffs = 0
    var hiddenSkips = 0
    var noChildrenLeaves = 0
    var roleCounts: [String: Int] = [:]
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

  private func traverse(
    _ element: AXUIElement,
    depth: Int,
    results: inout [DiscoveredElement],
    primaryHeight: CGFloat,
    roles: Set<String>,
    visibleRect: CGRect?,
    stats: inout TraversalStats
  ) {
    if depth > Self.maxDepth { stats.depthCutoffs += 1; return }
    if results.count >= Self.maxElements { stats.elementCutoffs += 1; return }
    guard !isCancelled else { return }

    stats.visited += 1
    stats.maxDepthReached = max(stats.maxDepthReached, depth)

    if isHidden(element) || !isEnabled(element) {
      stats.hiddenSkips += 1
      return
    }

    if let role = axRole(of: element) {
      stats.roleCounts[role, default: 0] += 1
      if roles.contains(role),
         let frame = axFrame(of: element, primaryHeight: primaryHeight),
         frame.width >= 4, frame.height >= 4,
         visibleRect.map({ $0.intersects(frame) }) ?? true {
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
          results.append(DiscoveredElement(element: element, screenFrame: frame, role: role, screen: screen))
        }
      }
    }

    let rawArr = axChildren(of: element)
    if rawArr.count == 0, depth <= 4 {
      var attrNames: CFArray?
      AXUIElementCopyAttributeNames(element, &attrNames)
      let names = (attrNames as? [String]) ?? []
      let role = axRole(of: element) ?? "?"
      // Detailed diagnosis: check what AXChildren actually returns
      var childRef: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(element, AXAttr.children as CFString, &childRef)
      let detail: String
      if err != .success {
        detail = "err=\(err.rawValue)"
      } else if let arr = childRef as? NSArray {
        detail = "empty(count=\(arr.count))"
      } else {
        detail = "type=\(childRef.map { CFGetTypeID($0) } ?? 0)"
      }
      Logger.info("AX scan: leaf \(role) at depth \(depth), children=\(detail), attrs=\(names)",
                  logger: Logger.pluginLifecycle)
      stats.noChildrenLeaves += 1
      return
    }
    guard rawArr.count > 0 else {
      stats.noChildrenLeaves += 1
      return
    }
    // CFArray of AXUIElement objects — map via unsafeBitCast to avoid CF conditional cast error
    let children = rawArr.map { unsafeBitCast($0 as AnyObject, to: AXUIElement.self) }

    for child in children {
      guard results.count < Self.maxElements else { break }
      traverse(child, depth: depth + 1, results: &results, primaryHeight: primaryHeight,
               roles: roles, visibleRect: visibleRect, stats: &stats)
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
         let arr = ref as? NSArray, arr.count > 0 {
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
