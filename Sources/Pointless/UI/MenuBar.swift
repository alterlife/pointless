import Cocoa
import Combine
import SwiftUI

/// Menu bar manager - displays plugin data and handles menu
@MainActor
class MenuBar {
  static let shared = MenuBar()

  private var statusItem: NSStatusItem?
  private var activeMenu: NSMenu?
  private var cancellables = Set<AnyCancellable>()

  private init() {}

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      let combinedView = MenuBarCombinedView()
      combinedView.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(combinedView)

      NSLayoutConstraint.activate([
        combinedView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        combinedView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        combinedView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        combinedView.heightAnchor.constraint(equalToConstant: 22)
      ])

      button.action = #selector(showMenu)
      button.target = self
    }
  }

  /// Dismiss the currently displayed menu (if any)
  static func dismissMenu() {
    shared.activeMenu?.cancelTracking()
  }

  @objc private func showMenu() {
    guard let button = statusItem?.button else { return }

    let menu = NSMenu()

    // Add widget detail views from WidgetRegistry
    for widget in WidgetRegistry.shared.orderedMenuWidgets {
      let menuItem = NSMenuItem()

      let contentView = ObservableWidgetView(widgetId: widget.id, ownerId: widget.ownerId) {
        widget.viewBuilder()
      }
      .frame(width: 360)
      .fixedSize(horizontal: false, vertical: true)

      let hostingView = NSHostingView(rootView: contentView)
      hostingView.translatesAutoresizingMaskIntoConstraints = false

      // Force layout to get proper size
      hostingView.layoutSubtreeIfNeeded()
      let intrinsicSize = hostingView.intrinsicContentSize
      let viewHeight = intrinsicSize.height > 0 ? intrinsicSize.height : 100
      hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: viewHeight)

      menuItem.view = hostingView
      menu.addItem(menuItem)
    }

    menu.addItem(NSMenuItem.separator())

    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    let quitItem = NSMenuItem(title: "Quit Pointless", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    activeMenu = menu
    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil
    activeMenu = nil
  }

  @objc private func openSettings() {
    SettingsWindowManager.shared.showSettings()
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
