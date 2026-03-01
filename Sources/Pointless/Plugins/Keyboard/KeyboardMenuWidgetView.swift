import SwiftUI

struct KeyboardMenuWidgetView: View {
  @ObservedObject var plugin: KeyboardPlugin

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      headerRow
      controlsRow
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
  }

  private var headerRow: some View {
    HStack {
      Image(systemName: "cursorarrow.click.2")
        .font(.title2)
        .foregroundColor(plugin.isEnabled ? .accentColor : .secondary)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text("Pointless")
            .font(.headline)
          Spacer()
          Text(plugin.shortcutDisplay)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }

        statusText
      }
    }
  }

  private var statusText: some View {
    HStack(spacing: 4) {
      if plugin.isEnabled {
        Text("Ready")
          .foregroundColor(.secondary)
        if plugin.sessionJumpCount > 0 {
          Text("·").foregroundColor(.secondary)
          Text("\(plugin.sessionJumpCount) jumps").foregroundColor(.secondary)
        }
      } else {
        Text("Disabled")
          .foregroundColor(.secondary)
      }
    }
    .font(.caption)
  }

  private var controlsRow: some View {
    HStack(spacing: 12) {
      Button {
        NotificationCenter.default.post(name: KeyboardPlugin.activateNotification, object: nil)
      } label: {
        Label("Activate", systemImage: "keyboard")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .disabled(!plugin.isEnabled)

      Spacer()

      Toggle("", isOn: Binding(
        get: { plugin.isEnabled },
        set: { plugin.configure(["enabled": $0]) }
      ))
      .toggleStyle(.switch)
      .controlSize(.small)
    }
  }
}
