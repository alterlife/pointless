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

/// SwiftUI view that renders all widget views
struct MenuBarContentView: View {
  @ObservedObject var widgetRegistry = WidgetRegistry.shared

  var body: some View {
    HStack(spacing: 0) {
      if widgetRegistry.orderedMenuBarWidgets.isEmpty {
        Image(systemName: "cursorarrow.click.2")
          .foregroundColor(.primary)
          .font(.system(size: 12))
      } else {
        ForEach(Array(widgetRegistry.orderedMenuBarWidgets.enumerated()), id: \.element.id) { index, widget in
          HStack(spacing: 0) {
            if index > 0 {
              Text(" | ")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            }

            ObservableWidgetView(widgetId: widget.id, pluginId: widget.pluginId) {
              widget.viewBuilder()
            }
          }
        }
      }
    }
    .padding(.horizontal, 4)
  }
}


