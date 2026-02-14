import SwiftUI

/// Combined view that displays all plugin menu bar views horizontally
class MenuBarCombinedView: NSView {
  private var hostingView: NSHostingView<MenuBarContentView>?

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
  }

  override var intrinsicContentSize: NSSize {
    // Forward the hosting view's intrinsic size so the status item sizes correctly
    return hostingView?.intrinsicContentSize ?? NSSize(width: 80, height: 22)
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
        ObservablePluginView(plugin: plugin) { observedPlugin in
          if let customView = observedPlugin.menuBarView() {
            return AnyView(MenuBarPluginViewWrapper(view: customView))
          } else {
            return AnyView(Text(observedPlugin.menuBarText).font(.system(size: 12)))
          }
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
