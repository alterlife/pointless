import SwiftUI
import PointlessCore

@main
struct PointlessApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var settingsWindow: NSWindow?

  var body: some Scene {
    Settings {
      SettingsView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }

  private func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Pointless Settings"
      window.contentView = NSHostingView(rootView: SettingsView())
      window.center()
      window.makeKeyAndOrderFront(nil)
      settingsWindow = window
    } else {
      settingsWindow?.makeKeyAndOrderFront(nil)
    }
  }
}
