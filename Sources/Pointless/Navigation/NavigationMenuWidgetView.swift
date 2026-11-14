import SwiftUI

struct NavigationMenuWidgetView: View {
  @ObservedObject var navigation: KeyboardNavigation

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
        .foregroundColor(navigation.isEnabled ? .accentColor : .secondary)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text("Pointless")
            .font(.headline)
          Spacer()
          Text(navigation.shortcutDisplay)
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
      if navigation.isEnabled {
        Text("Ready")
          .foregroundColor(.secondary)
        if navigation.sessionJumpCount > 0 {
          Text("·").foregroundColor(.secondary)
          Text("\(navigation.sessionJumpCount) jumps").foregroundColor(.secondary)
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
        MenuBar.dismissMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          NotificationCenter.default.post(name: KeyboardNavigation.activateNotification, object: nil)
        }
      } label: {
        Label("Activate", systemImage: "keyboard")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .disabled(!navigation.isEnabled)

      Spacer()

      Toggle("", isOn: Binding(
        get: { navigation.isEnabled },
        set: { navigation.configure(with: ["enabled": $0]) }
      ))
      .toggleStyle(.switch)
      .controlSize(.small)
    }
  }
}
