import AppKit
import OSLog
import SwiftUI

/// The core of Pointless: cursor-free navigation. Watches for the activation
/// hotkeys, owns the user-facing settings, and runs one `NavigationSession`
/// per activation (click overlay or scroll mode).
///
/// This is an app-level feature, not a plugin — the plugin system is for
/// optional monitoring widgets.
@MainActor
final class KeyboardNavigation: NSObject, ObservableObject {
  static let shared = KeyboardNavigation()

  static let activateNotification = Notification.Name("pointless.keyboard.activate")

  /// Settings storage id. Keeps the historical "plugin." prefix so existing
  /// user settings survive the keyboard feature's promotion out of the plugin system.
  let id = "pointless.keyboard"
  let name = "Pointless"
  let icon = "keyboard"

  @Published var isEnabled = true
  @Published var shortcutDisplay = "⌘⇧Space"
  @Published var scrollNextShortcutDisplay = "⌘⇧J"
  @Published var scrollPrevShortcutDisplay = "⌘⇧K"
  @Published var sessionJumpCount = 0
  @Published var lastScanCount = 0
  var captureShortcuts = true
  var isCapturingShortcut = false

  // Appearance settings
  @Published var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  @Published var badgeTextColor = Color.black
  @Published var badgeFontSize: CGFloat = 11
  @Published var showConnectorLines = true
  @Published var fadeInDuration = 0.08
  @Published var scrollSpeed = 1.0
  @Published var labelStrategy = "Homerow Keys"
  @Published var gridSwitchShortcutDisplay = "Tab"
  @Published var gridKeyClusterChoice = "Right Hand"
  @Published var gridAutoClick = true
  @Published var gridMaxLevelsChoice = "4 Levels"
  var gridSwitchShortcut = ParsedShortcut(modifiers: [], keyCode: 48)  // Tab
  var gridLetters: [Character] = LabelGenerator.rightHandGridLetters
  var gridMaxLevel: Int = 4

  var activationHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 49)  // Space
  var scrollNextHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 38)  // J
  var scrollPrevHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 40)  // K

  let overlayState = OverlayState()
  private(set) var session: NavigationSession?

  private var activationMonitor: Any?
  private var scrollMonitor: Any?
  private var hotkeyTap: HotkeyTap?
  private var appSwitchObserver: NSObjectProtocol?
  private var activationObserver: NSObjectProtocol?

  // MARK: - Lifecycle

  func start() {
    if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") {
      configure(with: saved)
    } else {
      applyAppearanceToOverlay()
      reinstallMonitors()
    }
    Logger.info("KeyboardNavigation start — isEnabled=\(isEnabled)", logger: Logger.pluginLifecycle)
    guard isEnabled else { return }
    activationObserver = NotificationCenter.default.addObserver(
      forName: Self.activateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.handleActivation() }
    }
    KeyboardOnboardingController.shared.showIfNeeded { [weak self] in
      Logger.info("KeyboardNavigation permissions granted", logger: Logger.pluginLifecycle)
      self?.reinstallMonitors()
    }
  }

  func stop() {
    session?.end()
    removeMonitors()
    if let observer = activationObserver {
      NotificationCenter.default.removeObserver(observer)
      activationObserver = nil
    }
  }

  func suspend() {
    session?.end()
  }

  func resume() {
    guard isEnabled else { return }
    // Global event monitors can stop working after sleep/wake — reinstall them
    reinstallMonitors()
  }

  // MARK: - Activation

  func handleActivation() {
    let onboarding = KeyboardOnboardingController.shared
    onboarding.refresh()
    guard onboarding.allGranted else {
      onboarding.ensurePermissions()
      return
    }

    if let session {
      session.end()
      return
    }
    beginSession { $0.beginClick() }
  }

  private func handleScrollActivation() {
    let onboarding = KeyboardOnboardingController.shared
    onboarding.refresh()
    guard onboarding.allGranted else {
      onboarding.ensurePermissions()
      return
    }
    // Already in a session (click overlay or scroll mode) — the session's
    // event tap handles further keys; ignore the global monitor.
    guard session == nil else { return }
    beginSession { $0.beginScroll() }
  }

  private func beginSession(_ begin: (NavigationSession) -> Void) {
    let newSession = NavigationSession(
      overlayState: overlayState,
      config: NavigationSession.Config(
        fadeInDuration: fadeInDuration,
        scrollSpeed: scrollSpeed,
        labelStrategy: labelStrategy == "Element Text"
          ? .useClickableElementText : .useHomeRowKeys,
        scrollNext: scrollNextHotkey,
        scrollPrev: scrollPrevHotkey,
        gridSwitchShortcut: gridSwitchShortcut,
        gridLetters: gridLetters,
        gridMaxLevel: gridMaxLevel,
        gridAutoClick: gridAutoClick
      ),
      onScanCompleted: { [weak self] count in self?.lastScanCount = count },
      onJump: { [weak self] in self?.sessionJumpCount += 1 },
      onEnded: { [weak self] in self?.session = nil }
    )
    session = newSession
    begin(newSession)
  }

  // MARK: - Global monitors

  func reinstallMonitors() {
    removeMonitors()
    guard isEnabled else { return }

    if captureShortcuts {
      installHotkeyTap()
    } else {
      installGlobalMonitors()
    }

    appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.session?.end() }
    }
  }

  private func installHotkeyTap() {
    let tap = HotkeyTap(
      activation: activationHotkey,
      scrollNext: scrollNextHotkey,
      scrollPrev: scrollPrevHotkey,
      shouldCapture: { [weak self] in
        guard let self else { return false }
        return self.session == nil && !self.isCapturingShortcut
      },
      onHotkey: { [weak self] hotkey in
        switch hotkey {
        case .activate: self?.handleActivation()
        case .scroll: self?.handleScrollActivation()
        }
      }
    )
    guard tap.start() else {
      installGlobalMonitors()
      return
    }
    hotkeyTap = tap
  }

  private func installGlobalMonitors() {
    let activation = activationHotkey
    activationMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, eventMatchesHotkey(event, keyCode: activation.keyCode, modifiers: activation.modifiers)
      else { return }
      Logger.info("KeyboardNavigation activation triggered", logger: Logger.pluginLifecycle)
      Task { @MainActor in self.handleActivation() }
    }

    let next = scrollNextHotkey
    let prev = scrollPrevHotkey
    scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return }
      if eventMatchesHotkey(event, keyCode: next.keyCode, modifiers: next.modifiers)
          || eventMatchesHotkey(event, keyCode: prev.keyCode, modifiers: prev.modifiers) {
        Task { @MainActor in self.handleScrollActivation() }
      }
    }
  }

  private func removeMonitors() {
    hotkeyTap?.stop()
    hotkeyTap = nil
    if let monitor = activationMonitor {
      NSEvent.removeMonitor(monitor)
      activationMonitor = nil
    }
    if let monitor = scrollMonitor {
      NSEvent.removeMonitor(monitor)
      scrollMonitor = nil
    }
    if let observer = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appSwitchObserver = nil
    }
  }
}

extension KeyboardNavigation {
  // MARK: - Widgets

  func menuBarWidgets() -> [MenuBarWidget] {
    [
      MenuBarWidget(id: "\(id).menubar", ownerId: id, name: "Navigation", priority: 1) {
        Image(systemName: "cursorarrow.click.2")
          .font(.system(size: 12))
          .foregroundColor(KeyboardNavigation.shared.isEnabled ? .primary : .secondary)
      }
    ]
  }

  func menuWidgets() -> [MenuWidget] {
    [
      MenuWidget(id: "\(id).detail", ownerId: id, name: "Navigation", priority: 50) {
        NavigationMenuWidgetView(navigation: self)
      }
    ]
  }
}

extension KeyboardNavigation: WidgetSource {}
