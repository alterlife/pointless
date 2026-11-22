import AppKit
import CoreGraphics

/// AppKit screen coords are bottom-left origin; CGEvent wants top-left.
/// The reflection resolves through the primary screen's height.
func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
  let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
  return CGPoint(x: point.x, y: primaryHeight - point.y)
}

// Click/drag timings follow Scoot's Mouse.swift — apps need the gaps
// between down/up events.
extension NavigationSession {
  func handleCursorKey(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.control) else { return false }
    switch event.keyCode {
    case 49:  // Space → left-click at cursor
      Self.postClick(at: currentCursorPoint())
      return true
    case 36:  // Return → right-click at cursor
      rightClickAtCursor()
      return true
    case 48:  // Tab → arm drag
      isDragArmed = true
      return true
    default:
      return false
    }
  }

  func activate(_ labeled: LabeledElement) {
    UserDefaults.standard.set(true, forKey: Self.clickHintKey)
    let element = labeled.element.element
    let center = labeled.element.screenFrame.center
    let clickPoint = cgPoint(fromAppKit: center)
    onJump()
    end()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      self.warpCursor(to: labeled.element)
      // AXPress beats a synthetic click — some apps ignore clicks at frame centers.
      if element.performPress() { return }
      Self.postClick(at: Self.unobscuredClickPoint(for: labeled.element) ?? clickPoint)
    }
  }

  func cursorActivate(_ labeled: LabeledElement) {
    if isDragArmed {
      isDragArmed = false
      teleportDrag(to: Self.cgCenter(of: labeled.element.screenFrame))
    } else {
      warpCursor(to: labeled.element)
    }
    updatePrefix("")
  }

  private func rightClickAtCursor() {
    Self.postRightClick(at: currentCursorPoint())
  }

  private func currentCursorPoint() -> CGPoint {
    cgPoint(fromAppKit: NSEvent.mouseLocation)
  }

  private static func cgCenter(of frame: CGRect) -> CGPoint {
    cgPoint(fromAppKit: CGPoint(x: frame.midX, y: frame.midY))
  }

  static func postClick(at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
      CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
              mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
  }

  static func postRightClick(at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
            mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
      CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
              mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
    }
  }

  static func unobscuredClickPoint(for discovered: NavigationTarget) -> CGPoint? {
    guard let app = AXElement.frontmostApplication() else { return nil }
    let frame = discovered.screenFrame
    let candidates: [(CGFloat, CGFloat)] = [
      (0.5, 0.5), (0.5, 0.3), (0.5, 0.7), (0.3, 0.5), (0.7, 0.5),
      (0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)
    ]
    var centerPoint: CGPoint?
    for (xFraction, yFraction) in candidates {
      let point = cgPoint(fromAppKit: CGPoint(
        x: frame.minX + frame.width * xFraction,
        y: frame.minY + frame.height * yFraction
      ))
      if centerPoint == nil { centerPoint = point }
      if let hit = app.elementAt(axX: point.x, axY: point.y),
         hit.isSameElement(as: discovered.element) || hit.isDescendant(of: discovered.element) {
        return point
      }
    }
    return centerPoint
  }

  private func teleportDrag(to end: CGPoint) {
    let start = currentCursorPoint()
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
      CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
              mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
      }
    }
  }
}
