import Cocoa
import Combine
import SwiftUI

/// Menu bar manager - displays plugin data and handles menu
@MainActor
class MenuBar {
  static let shared = MenuBar()

  private var statusItem: NSStatusItem?
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

      button.action = #selector(showMenu)
      button.target = self
    }
  }

  @objc private func showMenu() {
    guard let button = statusItem?.button else { return }

    let menu = NSMenu()

    // Add plugin detail views
    for plugin in PluginRegistry.shared.plugins {
      let menuItem = NSMenuItem()

      // Create SwiftUI content view
      let contentView = ObservablePluginView(plugin: plugin) { observedPlugin in
        observedPlugin.detailView()
      }
      .frame(width: 360)
      .fixedSize(horizontal: false, vertical: true)

      // Wrap in NSHostingView and size it
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

    // Add separator
    menu.addItem(NSMenuItem.separator())

    // Add Settings menu item
    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    // Add Quit menu item
    let quitItem = NSMenuItem(title: "Quit Pointless", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    // Display the menu
    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil
  }

  @objc private func openSettings() {
    SettingsWindowManager.shared.showSettings()
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
