import SwiftUI
import PointlessCore

@main
struct PointlessApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          SettingsWindowManager.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
}
