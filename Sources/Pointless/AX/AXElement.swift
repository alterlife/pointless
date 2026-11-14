import AppKit
import ApplicationServices

// MARK: - AX string constants (raw values, avoids dependency on kAXXXX constants,
// which the Swift module doesn't reliably expose under SPM)

enum AXRoleName {
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
  static let webArea = "AXWebArea"
  static let browser = "AXBrowser"
  static let application = "AXApplication"
  static let opaqueProviderGroup = "AXOpaqueProviderGroup"
}

private enum AXAttrName {
  static let role = "AXRole"
  static let enabled = "AXEnabled"
  static let hidden = "AXHidden"
  static let position = "AXPosition"
  static let size = "AXSize"
  static let parent = "AXParent"
  static let focusedWindow = "AXFocusedWindow"
  static let mainWindow = "AXMainWindow"
  static let focusedUIElement = "AXFocusedUIElement"
  static let enhancedUserInterface = "AXEnhancedUserInterface"
  static let manualAccessibility = "AXManualAccessibility"
  /// AXChildren first, then Firefox/Mullvad alternatives as fallbacks
  static let childAttrs = ["AXChildren", "AXChildrenInNavigationOrder", "AXVisibleChildren", "AXContents"]
}

private let axPressAction = "AXPress"

// MARK: - Coordinate conversion

/// Converts AX top-left-origin coordinates to NSScreen bottom-left-origin
internal func axToNSScreen(axOrigin: CGPoint, axSize: CGSize, primaryScreenHeight: CGFloat) -> CGRect {
  let nsScreenY = primaryScreenHeight - axOrigin.y - axSize.height
  return CGRect(x: axOrigin.x, y: nsScreenY, width: axSize.width, height: axSize.height)
}

// MARK: - AXElement

/// Typed facade over `AXUIElement`. All raw accessibility calls, CF cast workarounds,
/// and per-framework quirks live here so the rest of the codebase never touches them.
struct AXElement {
  let raw: AXUIElement

  // MARK: Construction

  static func application(pid: pid_t) -> AXElement {
    AXElement(raw: AXUIElementCreateApplication(pid))
  }

  /// The frontmost application's AX element, or nil when nothing is frontmost.
  static func frontmostApplication() -> AXElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return application(pid: app.processIdentifier)
  }

  // MARK: Attributes

  var role: String? {
    attributeValue(AXAttrName.role) as? String
  }

  var isEnabled: Bool {
    (attributeValue(AXAttrName.enabled) as? NSNumber)?.boolValue ?? true
  }

  var isHidden: Bool {
    (attributeValue(AXAttrName.hidden) as? NSNumber)?.boolValue ?? false
  }

  var parent: AXElement? {
    elementAttribute(AXAttrName.parent)
  }

  var focusedWindow: AXElement? {
    elementAttribute(AXAttrName.focusedWindow) ?? elementAttribute(AXAttrName.mainWindow)
  }

  var focusedUIElement: AXElement? {
    elementAttribute(AXAttrName.focusedUIElement)
  }

  /// Children via AXChildren, falling back to the alternative attributes some
  /// frameworks (Firefox, Mullvad) populate instead.
  var children: [AXElement] {
    for attr in AXAttrName.childAttrs {
      // swiftlint:disable:next empty_count
      guard let arr = attributeValue(attr) as? NSArray, arr.count > 0 else { continue }
      // CFArray of AXUIElement objects — conditional casts on AXUIElement don't compile,
      // so bridge via NSArray and rebind each element.
      return arr.map { AXElement(raw: unsafeBitCast($0 as AnyObject, to: AXUIElement.self)) }
    }
    return []
  }

  /// The element's frame in NSScreen (bottom-left origin) coordinates.
  func frame(primaryScreenHeight: CGFloat) -> CGRect? {
    guard let posValue = axValue(AXAttrName.position), let sizeValue = axValue(AXAttrName.size) else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posValue, .cgPoint, &position)
    AXValueGetValue(sizeValue, .cgSize, &size)
    return axToNSScreen(axOrigin: position, axSize: size, primaryScreenHeight: primaryScreenHeight)
  }

  // MARK: Actions

  /// Whether the element supports the AXPress action (clickable regardless of role)
  var supportsPress: Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(raw, &names) == .success,
          let actions = names as? [String] else { return false }
    return actions.contains(axPressAction)
  }

  @discardableResult
  func performPress() -> Bool {
    AXUIElementPerformAction(raw, axPressAction as CFString) == .success
  }

  // MARK: Hit testing

  /// The deepest element at a point in AX (top-left origin) coordinates.
  /// Position resolution pierces opaque provider boundaries that block tree traversal.
  func elementAt(axX: CGFloat, axY: CGFloat) -> AXElement? {
    var ref: AXUIElement?
    guard AXUIElementCopyElementAtPosition(raw, Float(axX), Float(axY), &ref) == .success,
          let hit = ref else { return nil }
    return AXElement(raw: hit)
  }

  // MARK: Assistive access (WebKit/Chromium lazy AX trees)

  /// WebKit/Chromium only expose their full AX tree to assistive clients — without this,
  /// web content (Safari pages, Electron apps) is an opaque group with no children.
  /// Returns true when the flag was newly enabled, in which case the tree is built
  /// lazily and callers should give the app a moment before traversing.
  @discardableResult
  func enableAssistiveAccess() -> Bool {
    let alreadyEnabled =
      (attributeValue(AXAttrName.enhancedUserInterface) as? NSNumber)?.boolValue ?? false
    AXUIElementSetAttributeValue(raw, AXAttrName.enhancedUserInterface as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(raw, AXAttrName.manualAccessibility as CFString, kCFBooleanTrue)
    return !alreadyEnabled
  }

  // MARK: Raw access helpers

  private func attributeValue(_ name: String) -> CFTypeRef? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(raw, name as CFString, &ref) == .success else { return nil }
    return ref
  }

  private func elementAttribute(_ name: String) -> AXElement? {
    guard let value = attributeValue(name) else { return nil }
    // AXUIElementCopyAttributeValue guarantees AXUIElement type for element attributes,
    // but a conditional cast on AXUIElement doesn't compile under SPM — rebind instead.
    return AXElement(raw: unsafeBitCast(value, to: AXUIElement.self))
  }

  private func axValue(_ name: String) -> AXValue? {
    guard let value = attributeValue(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    // CFGetTypeID verified — AXValue cast is safe here
    // swiftlint:disable:next force_cast
    return (value as! AXValue)
  }
}
