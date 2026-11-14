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
  private var captureShortcuts = true

  // Appearance settings
  @Published var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  @Published var badgeTextColor = Color.black
  @Published var badgeFontSize: CGFloat = 11
  @Published var showConnectorLines = true
  @Published var fadeInDuration = 0.08

  private var activationHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 49)  // Space
  private var scrollNextHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 38)  // J
  private var scrollPrevHotkey = ParsedShortcut(modifiers: [.command, .shift], keyCode: 40)  // K

  let overlayState = OverlayState()
  private(set) var session: NavigationSession?

  private var activationMonitor: Any?
  private var scrollMonitor: Any?
  private var hotkeyTap: HotkeyTap?
  private var appSwitchObserver: NSObjectProtocol?
  private var activationObserver: NSObjectProtocol?

  // MARK: - Settings

  private let settingDefinitions: [SettingDefinition] = [
    .section(label: "Activation", description: "Keyboard shortcut and enable/disable"),
    .toggle(key: "enabled", label: "Enabled", defaultValue: true),
    .hotkey(key: "activationHotkey", label: "Activation Shortcut", defaultValue: "⌘⇧Space"),
    .toggle(
      key: "captureShortcuts",
      label: "Capture Shortcuts",
      defaultValue: true,
      description: "Pointless consumes its shortcuts so apps never see them — e.g. ⌘⇧J won't also " +
        "trigger an app's own shortcut. Turn off to let shortcuts pass through to apps."
    ),
    .section(label: "Scroll Mode", description: "Cycle and scroll scrollable areas by keyboard"),
    .hotkey(key: "scrollNextHotkey", label: "Scroll / Next Area", defaultValue: "⌘⇧J"),
    .hotkey(key: "scrollPrevHotkey", label: "Previous Scroll Area", defaultValue: "⌘⇧K"),
    .section(label: "Overlay Style", description: "Customize the letter hints on screen elements"),
    .color(key: "badgeColor", label: "Hint Color", defaultValue: "#F2BF1A"),
    .color(key: "textColor", label: "Hint Text Color", defaultValue: "#000000"),
    .slider(key: "fontSize", label: "Hint Size", range: 9...16, defaultValue: 11, step: 1),
    .toggle(key: "showLines", label: "Lines to Targets", defaultValue: true),
    .slider(key: "fadeIn", label: "Appear Speed", range: 0...0.3, defaultValue: 0.08, step: 0.02)
  ]

  func settings() -> PluginSettings {
    PluginSettings(definitions: settingDefinitions)
  }

  func configure(with values: [String: Any]) {
    if let enabled = values["enabled"] as? Bool { isEnabled = enabled }
    if let capture = values["captureShortcuts"] as? Bool { captureShortcuts = capture }
    if let hex = values["badgeColor"] as? String {
      badgeColor = Color(hex: hex) ?? Color(red: 0.95, green: 0.75, blue: 0.1)
    }
    if let hex = values["textColor"] as? String {
      badgeTextColor = Color(hex: hex) ?? .black
    }
    if let size = values["fontSize"] as? Double { badgeFontSize = CGFloat(size) }
    if let lines = values["showLines"] as? Bool { showConnectorLines = lines }
    if let fade = values["fadeIn"] as? Double { fadeInDuration = fade }
    if let shortcut = values["activationHotkey"] as? String {
      shortcutDisplay = shortcut
      activationHotkey = parseShortcutString(shortcut)
    }
    if let shortcut = values["scrollNextHotkey"] as? String {
      scrollNextShortcutDisplay = shortcut
      scrollNextHotkey = parseShortcutString(shortcut)
    }
    if let shortcut = values["scrollPrevHotkey"] as? String {
      scrollPrevShortcutDisplay = shortcut
      scrollPrevHotkey = parseShortcutString(shortcut)
    }
    applyAppearanceToOverlay()
    reinstallMonitors()
    saveSettings(values)
  }

  private func saveSettings(_ values: [String: Any]) {
    var stored = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") ?? [:]
    values.forEach { stored[$0.key] = $0.value }
    UserDefaults.standard.set(stored, forKey: "plugin.\(id)")
  }

  private func applyAppearanceToOverlay() {
    overlayState.badgeColor = badgeColor
    overlayState.textColor = badgeTextColor
    overlayState.badgeFontSize = badgeFontSize
    overlayState.showConnectorLines = showConnectorLines
    overlayState.fadeInDuration = fadeInDuration
  }

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
    KeyboardOnboardingController.shared.showIfNeeded {
      Logger.info("KeyboardNavigation permissions granted", logger: Logger.pluginLifecycle)
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
        scrollNext: scrollNextHotkey,
        scrollPrev: scrollPrevHotkey
      ),
      onScanCompleted: { [weak self] count in self?.lastScanCount = count },
      onJump: { [weak self] in self?.sessionJumpCount += 1 },
      onEnded: { [weak self] in self?.session = nil }
    )
    session = newSession
    begin(newSession)
  }

  // MARK: - Global monitors

  private func reinstallMonitors() {
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
      shouldCapture: { [weak self] in self?.session == nil },
      onHotkey: { [weak self] hotkey in
        switch hotkey {
        case .activate: self?.handleActivation()
        case .scroll: self?.handleScrollActivation()
        }
      }
    )
    tap.start()
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
