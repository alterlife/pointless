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
    let point = currentCursorPoint()
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
            mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
    usleep(10_000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
            mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
  }

  private func currentCursorPoint() -> CGPoint {
    cgPoint(fromAppKit: NSEvent.mouseLocation)
  }

  private static func cgCenter(of frame: CGRect) -> CGPoint {
    cgPoint(fromAppKit: CGPoint(x: frame.midX, y: frame.midY))
  }

  private func teleportDrag(to end: CGPoint) {
    let start = currentCursorPoint()
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(200_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
  }
}
