import Cocoa
import SwiftUI

/// Manages the settings window to ensure only one instance exists
public class SettingsWindowManager {
  public static let shared = SettingsWindowManager()

  private var settingsWindow: NSWindow?
  private var windowDelegate: WindowDelegate?

  private init() {}

  public func showSettings() {
    if let window = settingsWindow, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Pointless Settings"
    window.contentView = NSHostingView(rootView: SettingsView())
    window.center()
    window.isReleasedWhenClosed = false  // Keep reference when closed

    // Set delegate to handle window close (keep strong reference)
    let delegate = WindowDelegate()
    window.delegate = delegate
    windowDelegate = delegate

    settingsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    // Window will close but reference will remain for reuse
  }
}
