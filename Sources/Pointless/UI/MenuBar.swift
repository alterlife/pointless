import Cocoa
import SwiftUI
import Combine

/// Menu bar manager - displays plugin data and handles popover
@MainActor
class MenuBar {
  static let shared = MenuBar()

  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var cancellables = Set<AnyCancellable>()

  private init() {}

  func setup() {
    // Create status item with variable length (auto-sizing)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // Set up click action
    if let button = statusItem?.button {
      // Add custom view as subview
      let combinedView = MenuBarCombinedView()
      combinedView.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(combinedView)

      NSLayoutConstraint.activate([
        combinedView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        combinedView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        combinedView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        combinedView.heightAnchor.constraint(equalToConstant: 22)
      ])

      button.action = #selector(togglePopover)
      button.target = self
    }

    // Create popover
    popover = NSPopover()
    popover?.contentSize = NSSize(width: 360, height: 400)
    popover?.behavior = .transient
    popover?.contentViewController = NSHostingController(rootView: PopoverView())
  }

  @objc private func togglePopover() {
    guard let button = statusItem?.button else { return }

    if popover?.isShown == true {
      popover?.performClose(nil)
    } else {
      popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }

}
