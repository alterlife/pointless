import SwiftUI
import Combine

/// Combined view that displays all plugin menu bar views horizontally
class MenuBarCombinedView: NSView {
  private var hostingView: NSHostingView<MenuBarContentView>?
  private var cancellables = Set<AnyCancellable>()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    let contentView = MenuBarContentView()
    hostingView = NSHostingView(rootView: contentView)

    if let hostingView = hostingView {
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hostingView)

      NSLayoutConstraint.activate([
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: trailingAnchor)
      ])
    }

    // Update when plugins change
    PluginRegistry.shared.$plugins
      .sink { [weak self] _ in
        self?.updateContent()
      }
      .store(in: &cancellables)

    // Also update periodically (plugin data changes)
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateContent()
    }
  }

  private func updateContent() {
    // Trigger SwiftUI view update
    hostingView?.rootView = MenuBarContentView()
  }
}

/// SwiftUI view that renders all plugin views
struct MenuBarContentView: View {
  @ObservedObject var registry = PluginRegistry.shared

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(registry.plugins.enumerated()), id: \.element.id) { index, plugin in
        if index > 0 {
          Text(" | ")
            .foregroundColor(.secondary)
            .font(.system(size: 12))
        }

        // Use custom view if provided, otherwise fall back to text
        if let customView = plugin.menuBarView() {
          MenuBarPluginViewWrapper(view: customView)
        } else {
          Text(plugin.menuBarText)
            .font(.system(size: 12))
        }
      }
    }
    .padding(.horizontal, 4)
  }
}

/// Wrapper to embed NSView in SwiftUI
struct MenuBarPluginViewWrapper: NSViewRepresentable {
  let view: NSView

  func makeNSView(context: Context) -> NSView {
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    // View updates handled by plugin
  }
}
