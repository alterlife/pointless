import AppKit
import CoreGraphics
import OSLog
import SwiftUI

// MARK: - KeyboardPlugin

final class KeyboardPlugin: NSObject, ObservableObject, Plugin {
  static let activateNotification = Notification.Name("pointless.keyboard.activate")

  let id = "pointless.keyboard"
  let name = "Pointless"
  let icon = "keyboard"

  @Published var menuBarText = "⌨"
  @Published var isEnabled = true
  @Published var shortcutDisplay = "⌘⇧Space"
  @Published var scrollNextShortcutDisplay = "⌘⇧J"
  @Published var scrollPrevShortcutDisplay = "⌘⇧K"
  @Published var sessionJumpCount = 0
  @Published var lastScanCount = 0

  // Appearance settings
  @Published var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  @Published var badgeTextColor = Color.black
  @Published var badgeFontSize: CGFloat = 11
  @Published var showConnectorLines = true
  @Published var fadeInDuration = 0.08

  // Click activation hotkey
  private var hotkeyCode: UInt16 = 49  // Space
  private var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
  private var activationObserver: NSObjectProtocol?

  // Scroll hotkeys — internal so extensions can access them
  var scrollNextCode: UInt16 = 38  // J
  var scrollNextMods: NSEvent.ModifierFlags = [.command, .shift]
  var scrollPrevCode: UInt16 = 40  // K
  var scrollPrevMods: NSEvent.ModifierFlags = [.command, .shift]
  var scrollMonitor: Any?

  // Internal so extensions can pattern-match and update phase
  enum OverlayPhase {
    case inactive
    case scanning
    case active(typedSoFar: String)
    case scrolling(targets: [DiscoveredElement], currentIndex: Int)
  }

  var phase: OverlayPhase = .inactive
  let overlayState = OverlayState()
  var overlayWindows: [ElementOverlayWindow] = []
  var labeledElements: [LabeledElement] = []

  private var activationMonitor: Any?
  private var appSwitchObserver: NSObjectProtocol?
  var eventTap: CFMachPort?
  var scanner: AccessibilityScanner?

  override init() {
    super.init()
    initialize()
  }

  func initialize() {
    declareSettings([
      .section(label: "Activation", description: "Keyboard shortcut and enable/disable"),
      .toggle(key: "enabled", label: "Enabled", defaultValue: true),
      .hotkey(key: "activationHotkey", label: "Activation Shortcut", defaultValue: "⌘⇧Space"),
      .section(label: "Scroll Mode", description: "Cycle and scroll scrollable areas by keyboard"),
      .hotkey(key: "scrollNextHotkey", label: "Scroll / Next Area", defaultValue: "⌘⇧J"),
      .hotkey(key: "scrollPrevHotkey", label: "Previous Scroll Area", defaultValue: "⌘⇧K"),
      .section(label: "Overlay Style", description: "Customize the letter hints on screen elements"),
      .color(key: "badgeColor", label: "Hint Color", defaultValue: "#F2BF1A"),
      .color(key: "textColor", label: "Hint Text Color", defaultValue: "#000000"),
      .slider(key: "fontSize", label: "Hint Size", range: 9...16, defaultValue: 11, step: 1),
      .toggle(key: "showLines", label: "Lines to Targets", defaultValue: true),
      .slider(key: "fadeIn", label: "Appear Speed", range: 0...0.3, defaultValue: 0.08, step: 0.02)
    ])
  }

  // MARK: - Plugin Protocol

  func configure(with values: [String: Any]) {
    if let enabled = values["enabled"] as? Bool { isEnabled = enabled }
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
      let parsed = parseShortcutString(shortcut)
      self.hotkeyModifiers = parsed.modifiers
      self.hotkeyCode = parsed.keyCode
      Task { @MainActor in
        self.stopActivationMonitor()
        self.startActivationMonitor()
      }
    }
    var scrollMonitorsNeedRestart = false
    if let shortcut = values["scrollNextHotkey"] as? String {
      scrollNextShortcutDisplay = shortcut
      let parsed = parseShortcutString(shortcut)
      scrollNextMods = parsed.modifiers
      scrollNextCode = parsed.keyCode
      scrollMonitorsNeedRestart = true
    }
    if let shortcut = values["scrollPrevHotkey"] as? String {
      scrollPrevShortcutDisplay = shortcut
      let parsed = parseShortcutString(shortcut)
      scrollPrevMods = parsed.modifiers
      scrollPrevCode = parsed.keyCode
      scrollMonitorsNeedRestart = true
    }
    if scrollMonitorsNeedRestart {
      Task { @MainActor in
        self.stopScrollMonitors()
        self.startScrollMonitors()
      }
    }
    Task { @MainActor in self.applySettingsToState() }
    saveSettings(values)
  }

  func start() {
    Task { @MainActor in
      if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(self.id)") { self.configure(with: saved) }
      Logger.info("KeyboardPlugin start — isEnabled=\(self.isEnabled)", logger: Logger.pluginLifecycle)
      guard self.isEnabled else { return }
      self.startActivationMonitor()
      self.activationObserver = NotificationCenter.default.addObserver(
        forName: Self.activateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.handleActivation() }
      }
      KeyboardOnboardingController.shared.showIfNeeded {
        Logger.info("KeyboardPlugin permissions granted", logger: Logger.pluginLifecycle)
      }
    }
  }

  func stop() {
    Task { @MainActor in
      self.dismissOverlay()
      self.stopActivationMonitor()
      if let observer = self.activationObserver {
        NotificationCenter.default.removeObserver(observer)
        self.activationObserver = nil
      }
      Logger.info("Stopped plugin \(self.id)")
    }
  }

  func suspend() {
    Task { @MainActor in self.cancelActiveMode() }
  }

  /// Dismiss whatever mode is active (click overlay or scroll mode). Shared by
  /// suspend(), app-switch observer, and any other interruption path.
  @MainActor
  func cancelActiveMode() {
    switch phase {
    case .active: dismissOverlay()
    case .scrolling: exitScrollMode()
    default: break
    }
  }

  func resume() {
    Task { @MainActor in
      guard self.isEnabled else { return }
      // Global event monitors can stop working after sleep/wake — reinstall them
      self.stopActivationMonitor()
      self.startActivationMonitor()
    }
  }

  // MARK: - Settings → State

  @MainActor
  private func applySettingsToState() {
    overlayState.badgeColor = badgeColor
    overlayState.textColor = badgeTextColor
    overlayState.badgeFontSize = badgeFontSize
    overlayState.showConnectorLines = showConnectorLines
    overlayState.fadeInDuration = fadeInDuration
  }

  // MARK: - Activation Monitor

  private func startActivationMonitor() {
    let expectedCode = hotkeyCode
    let expectedMods = hotkeyModifiers
    activationMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, eventMatchesHotkey(event, keyCode: expectedCode, modifiers: expectedMods) else { return }
      Logger.info("KeyboardPlugin activation triggered", logger: Logger.pluginLifecycle)
      Task { @MainActor in self.handleActivation() }
    }
    Logger.info(
      "KeyboardPlugin activation monitor installed: \(self.activationMonitor != nil)",
      logger: Logger.pluginLifecycle
    )

    appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.cancelActiveMode() }
    }

    startScrollMonitors()
  }

  private func stopActivationMonitor() {
    if let monitor = activationMonitor {
      NSEvent.removeMonitor(monitor)
      activationMonitor = nil
    }
    if let observer = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appSwitchObserver = nil
    }
    stopScrollMonitors()
    stopNavigationMonitor()
  }

  // MARK: - Key Handling

  @MainActor
  func handleNavigationKey(_ event: NSEvent) {
    switch phase {
    case .active(let prefix):
      switch event.keyCode {
      case 53:  // ESC
        dismissOverlay()
      case 51:  // Backspace
        updatePrefix(String(prefix.dropLast()))
      default:
        guard let char = event.charactersIgnoringModifiers?.lowercased().first,
              LabelGenerator.priorityKeys.contains(char) else { return }
        let newPrefix = prefix + String(char)
        if let match = LabelGenerator.exactMatch(in: labeledElements, for: newPrefix) {
          activateElement(match)
        } else if LabelGenerator.filter(labeledElements, prefix: newPrefix).isEmpty {
          dismissOverlay()
        } else {
          updatePrefix(newPrefix)
        }
      }
    case .scrolling(let targets, let currentIndex):
      handleScrollKey(event, targets: targets, currentIndex: currentIndex)
    default:
      break
    }
  }

  @MainActor
  private func updatePrefix(_ prefix: String) {
    phase = .active(typedSoFar: prefix)
    overlayState.typedPrefix = prefix
  }

  // MARK: - Dismiss & Click Synthesis

  @MainActor
  func dismissOverlay() {
    phase = .inactive
    scanner?.cancel()
    scanner = nil
    stopNavigationMonitor()
    overlayWindows.forEach { $0.hide() }
    overlayState.labeledElements = []
    overlayState.typedPrefix = ""
    overlayState.scrollTargetFrame = nil
  }

  @MainActor
  private func activateElement(_ labeled: LabeledElement) {
    sessionJumpCount += 1
    dismissOverlay()
    let axElement = labeled.element.element
    let center = labeled.element.screenFrame.center
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let cgPoint = CGPoint(x: center.x, y: primaryHeight - center.y)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      // AXPress is more reliable than a synthetic click (e.g. Terminal tabs ignore
      // clicks at their frame center). Fall back to a click for elements without it.
      if AXUIElementPerformAction(axElement, "AXPress" as CFString) == .success { return }
      CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
              mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
      CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
              mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
  }

  // MARK: - Widgets

  func menuBarWidgets() -> [MenuBarWidget] {
    [
      MenuBarWidget(id: "\(id).menubar", pluginId: id, name: "Navigation", priority: 1) {
        Image(systemName: "cursorarrow.click.2")
          .font(.system(size: 12))
          .foregroundColor(self.isEnabled ? .primary : .secondary)
      }
    ]
  }

  func menuWidgets() -> [MenuWidget] {
    [
      MenuWidget(id: "\(id).detail", pluginId: id, name: "Navigation", priority: 50) {
        KeyboardMenuWidgetView(plugin: self)
      }
    ]
  }
}
