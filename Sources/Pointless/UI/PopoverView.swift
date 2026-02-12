import SwiftUI

struct PopoverView: View {
  @ObservedObject var registry = PluginRegistry.shared

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Pointless")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Button(action: openSettings) {
          Image(systemName: "gear")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        Button(action: { NSApplication.shared.terminate(nil) }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding()

      Divider()

      // Plugin cards
      ScrollView {
        VStack(spacing: 12) {
          ForEach(registry.plugins, id: \.id) { plugin in
            plugin.detailView()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(NSColor.controlBackgroundColor))
              .cornerRadius(8)
          }
        }
        .padding()
      }
    }
    .frame(width: 360, height: 400)
  }

  private func openSettings() {
    // Create and show settings window
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
    NSApp.activate(ignoringOtherApps: true)
  }
}
