import AppKit
import SwiftUI

/// NSView that becomes first responder to capture keyDown events directly.
/// This works reliably in menu bar apps where NSEvent local monitors may not fire.
final class ShortcutCaptureView: NSView {
  var shortcutDisplay = ""
  var recording = false
  var onShortcutCaptured: ((String) -> Void)?
  var onCancelRecording: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 28)
  }

  override func becomeFirstResponder() -> Bool {
    needsDisplay = true
    return true
  }

  override func resignFirstResponder() -> Bool {
    needsDisplay = true
    return true
  }

  override func mouseDown(with event: NSEvent) {
    if !recording {
      recording = true
      window?.makeFirstResponder(self)
      needsDisplay = true
    }
  }

  override func keyDown(with event: NSEvent) {
    guard recording else {
      super.keyDown(with: event)
      return
    }

    // ESC cancels recording
    if event.keyCode == 53 {
      onCancelRecording?()
      return
    }

    let modifiers = event.modifierFlags.intersection(
      [.command, .shift, .option, .control]
    )
    // Require at least one modifier for a valid shortcut
    guard !modifiers.isEmpty else { return }

    let display = Self.modifierSymbols(modifiers) + Self.keyName(from: event)
    onShortcutCaptured?(display)
  }

  override func draw(_ dirtyRect: NSRect) {
    let bounds = self.bounds

    // Background
    let bgColor: NSColor = recording
      ? NSColor.controlAccentColor.withAlphaComponent(0.1)
      : NSColor.controlBackgroundColor
    bgColor.setFill()
    let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
    bgPath.fill()

    // Border
    let borderColor: NSColor = recording
      ? NSColor.controlAccentColor
      : NSColor.separatorColor
    borderColor.setStroke()
    let borderPath = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      xRadius: 6,
      yRadius: 6
    )
    borderPath.lineWidth = recording ? 2 : 1
    borderPath.stroke()

    // Text
    let text = recording ? "Press shortcut\u{2026}" : shortcutDisplay
    let textColor: NSColor = recording ? .secondaryLabelColor : .labelColor
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor
    ]
    let attrString = NSAttributedString(string: text, attributes: attrs)
    let textSize = attrString.size()
    let textOrigin = NSPoint(
      x: 8,
      y: (bounds.height - textSize.height) / 2
    )
    attrString.draw(at: textOrigin)
  }

  // MARK: - Key name helpers

  static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var result = ""
    if flags.contains(.control) { result += "\u{2303}" }
    if flags.contains(.option) { result += "\u{2325}" }
    if flags.contains(.shift) { result += "\u{21E7}" }
    if flags.contains(.command) { result += "\u{2318}" }
    return result
  }

  static func keyName(from event: NSEvent) -> String {
    switch event.keyCode {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 51: return "Delete"
    case 53: return "Esc"
    case 123: return "\u{2190}"
    case 124: return "\u{2192}"
    case 125: return "\u{2193}"
    case 126: return "\u{2191}"
    default:
      return event.charactersIgnoringModifiers?.uppercased() ?? "Key\(event.keyCode)"
    }
  }
}
