import AppKit
import CoreGraphics
import OSLog
import SwiftUI

// MARK: - CGEventTap free function (C callback — must be top-level)

private func keyboardPluginEventCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent?,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let event else { return nil }
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let plugin = Unmanaged<KeyboardPlugin>.fromOpaque(userInfo).takeUnretainedValue()

  if type == .leftMouseDown || type == .rightMouseDown {
    Task { @MainActor in plugin.dismissOverlay() }
    return Unmanaged.passUnretained(event)
  }

  if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
    Task { @MainActor in plugin.handleNavigationKey(nsEvent) }
    return nil
  }

  return Unmanaged.passUnretained(event)
}

// MARK: - KeyboardPlugin

final class KeyboardPlugin: NSObject, ObservableObject, Plugin {
  static let activateNotification = Notification.Name("pointless.keyboard.activate")

  let id = "pointless.keyboard"
  let name = "Pointless"
  let icon = "keyboard"

  @Published var menuBarText = "⌨"
  @Published var isEnabled = true
  @Published var shortcutDisplay = "⌘⇧Space"
  @Published var sessionJumpCount = 0
  @Published var lastScanCount = 0

  // Appearance settings
  @Published var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  @Published var badgeTextColor = Color.black
  @Published var badgeFontSize: CGFloat = 11
  @Published var showConnectorLines = true
  @Published var fadeInDuration = 0.08

  // Activation hotkey (parsed from display string like "⌘⇧Space")
  private var hotkeyCode: UInt16 = 49  // Space
  private var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
  private var activationObserver: NSObjectProtocol?

  private enum OverlayPhase {
    case inactive
    case scanning
    case active(typedSoFar: String)
  }

  private var phase: OverlayPhase = .inactive
  private let overlayState = OverlayState()
  private var overlayWindows: [ElementOverlayWindow] = []
  private var labeledElements: [LabeledElement] = []

  private var activationMonitor: Any?
  private var appSwitchObserver: NSObjectProtocol?
  private var eventTap: CFMachPort?
  private var scanner: AccessibilityScanner?

  override init() {
    super.init()
    initialize()
  }

  func initialize() {
    declareSettings([
      .section(label: "Activation", description: "Keyboard shortcut and enable/disable"),
      .toggle(key: "enabled", label: "Enabled", defaultValue: true),
      .hotkey(key: "activationHotkey", label: "Activation Shortcut", defaultValue: "⌘⇧Space"),
      .section(label: "Overlay Style", description: "Customize the letter hints on screen elements"),
      .color(key: "badgeColor", label: "Hint Color", defaultValue: "#F2BF1A"),
      .color(key: "textColor", label: "Hint Text Color", defaultValue: "#000000"),
      .slider(key: "fontSize", label: "Hint Size", range: 9...16, defaultValue: 11, step: 1),
      .toggle(key: "showLines", label: "Lines to Targets", defaultValue: true),
      .slider(key: "fadeIn", label: "Appear Speed", range: 0...0.3, defaultValue: 0.08, step: 0.02)
    ])
  }

  // MARK: - Plugin Protocol

  func configure(_ values: [String: Any]) {
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
    Task { @MainActor in self.applySettingsToState() }
    saveSettings(values)
  }

  func start() {
    Task { @MainActor in
      if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(self.id)") { self.configure(saved) }
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
    Task { @MainActor in
      if case .active = self.phase { self.dismissOverlay() }
    }
  }

  func resume() {
    // Activation monitor is still running; nothing to restart
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
      guard let self else { return }
      let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
      let pressed = event.modifierFlags.intersection(relevantFlags)
      guard event.keyCode == expectedCode, pressed == expectedMods else { return }
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
      Task { @MainActor in
        if case .active = self.phase { self.dismissOverlay() }
      }
    }
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
    stopNavigationMonitor()
  }

  // MARK: - Overlay Activation

  @MainActor
  private func handleActivation() {
    // If permissions aren't granted, show onboarding instead of activating
    let onboarding = KeyboardOnboardingController.shared
    onboarding.refresh()
    guard onboarding.allGranted else {
      onboarding.ensurePermissions()
      return
    }

    if case .active = phase {
      dismissOverlay()
      return
    }
    phase = .scanning
    rebuildOverlayWindows()

    let scan = AccessibilityScanner()
    scanner = scan
    scan.scan { [weak self] elements in
      guard let self else { return }
      guard !elements.isEmpty else {
        Logger.warning("No interactive elements found in focused window", logger: Logger.pluginLifecycle)
        self.phase = .inactive
        self.overlayWindows.forEach { $0.hide() }
        showEmptyHint()
        return
      }
      let sorted = elements.sorted { lhs, rhs in
        if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
        return lhs.screenFrame.minX < rhs.screenFrame.minX
      }
      let labeled = LabelGenerator.label(sorted)
      self.lastScanCount = elements.count
      self.labeledElements = labeled
      self.overlayState.labeledElements = labeled
      self.overlayState.typedPrefix = ""
      self.phase = .active(typedSoFar: "")
      self.overlayWindows.forEach { $0.show(fadeDuration: self.fadeInDuration) }
      self.startNavigationMonitor()
    }
  }

  private func rebuildOverlayWindows() {
    overlayWindows.forEach { $0.hide() }
    overlayWindows = NSScreen.screens.map { ElementOverlayWindow(screen: $0, state: overlayState) }
  }

  // MARK: - Navigation Monitor (CGEventTap)

  private func startNavigationMonitor() {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                          | (1 << CGEventType.leftMouseDown.rawValue)
                          | (1 << CGEventType.rightMouseDown.rawValue)
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: keyboardPluginEventCallback,
      userInfo: selfPtr
    ) else {
      Logger.error("Failed to create CGEventTap — Input Monitoring permission may be missing")
      Task { @MainActor in self.dismissOverlay() }
      return
    }
    eventTap = tap
    if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func stopNavigationMonitor() {
    guard let tap = eventTap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    eventTap = nil
  }

  // MARK: - Key Handling

  @MainActor
  func handleNavigationKey(_ event: NSEvent) {
    guard case .active(let prefix) = phase else { return }
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
  }

  @MainActor
  private func activateElement(_ labeled: LabeledElement) {
    sessionJumpCount += 1
    dismissOverlay()
    let center = labeled.element.screenFrame.center
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let cgPoint = CGPoint(x: center.x, y: primaryHeight - center.y)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
