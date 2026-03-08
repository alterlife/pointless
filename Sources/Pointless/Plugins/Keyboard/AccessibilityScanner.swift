import AppKit
import ApplicationServices

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
  private static let interactiveRoles: Set<String> = [
    AXRole.button, AXRole.link, AXRole.textField, AXRole.textArea,
    AXRole.checkBox, AXRole.radioButton, AXRole.popUpButton, AXRole.menuItem,
    AXRole.comboBox, AXRole.tabGroup, AXRole.disclosureTriangle,
    AXRole.incrementor, AXRole.slider
  ]

  private static let maxDepth = 12
  private static let maxElements = 150

  private var isCancelled = false

  func cancel() {
    isCancelled = true
  }

  func scan(completion: @escaping @MainActor ([DiscoveredElement]) -> Void) {
    isCancelled = false
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        Task { @MainActor in completion([]) }
        return
      }
      let elements = self.performScan()
      Task { @MainActor in completion(elements) }
    }
  }

  private func performScan() -> [DiscoveredElement] {
    guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let window = focusedWindow(from: axApp) else { return [] }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    var results: [DiscoveredElement] = []
    traverse(window, depth: 0, results: &results, primaryHeight: primaryHeight)
    return results
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
    primaryHeight: CGFloat
  ) {
    guard !isCancelled, depth <= Self.maxDepth, results.count < Self.maxElements else { return }
    guard !isHidden(element), isEnabled(element) else { return }

    if let role = axRole(of: element), Self.interactiveRoles.contains(role),
       let frame = axFrame(of: element, primaryHeight: primaryHeight),
       frame.width >= 4, frame.height >= 4 {
      if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main {
        results.append(DiscoveredElement(element: element, screenFrame: frame, role: role, screen: screen))
      }
    }

    var childrenRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, AXAttr.children as CFString, &childrenRef) == .success,
          let rawArr = childrenRef as? NSArray else { return }
    // CFArray of AXUIElement objects — map via unsafeBitCast to avoid CF conditional cast error
    let children = rawArr.map { unsafeBitCast($0 as AnyObject, to: AXUIElement.self) }

    for child in children {
      guard results.count < Self.maxElements else { break }
      traverse(child, depth: depth + 1, results: &results, primaryHeight: primaryHeight)
    }
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
