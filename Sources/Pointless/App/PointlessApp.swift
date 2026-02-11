import SwiftUI

@main
struct PointlessApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
    }
  }
}
