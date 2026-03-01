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
  let id = "pointless.keyboard"
  let name = "Jump"

  @Published var menuBarText = "⌨"
  @Published var isEnabled = true

  // Appearance settings
  @Published var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  @Published var badgeTextColor = Color.black
  @Published var badgeFontSize: CGFloat = 11
  @Published var showConnectorLines = true
  @Published var fadeInDuration = 0.08

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
      .section(label: "General"),
      .toggle(key: "enabled", label: "Enabled", defaultValue: true),
      .section(label: "Shortcut"),
      .hotkey(key: "activationHotkey", label: "Activation Shortcut", defaultValue: "⌘⇧Space"),
      .section(label: "Appearance"),
      .color(key: "badgeColor", label: "Badge Color", defaultValue: "#F2BF1A"),
      .color(key: "textColor", label: "Label Color", defaultValue: "#000000"),
      .slider(key: "fontSize", label: "Label Font Size", range: 9...16, defaultValue: 11, step: 1),
      .toggle(key: "showLines", label: "Show Connector Lines", defaultValue: true),
      .slider(key: "fadeIn", label: "Fade In (s)", range: 0...0.3, defaultValue: 0.08, step: 0.02)
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
    Task { @MainActor in self.applySettingsToState() }
    saveSettings(values)
  }

  func start() {
    Task { @MainActor in
      if let saved = UserDefaults.standard.dictionary(forKey: "plugin.\(self.id)") { self.configure(saved) }
      Logger.info("KeyboardPlugin start — isEnabled=\(self.isEnabled)", logger: Logger.pluginLifecycle)
      guard self.isEnabled else { return }
      KeyboardOnboardingController.shared.showIfNeeded { [weak self] in
        Logger.info("KeyboardPlugin onboarding complete — installing activation monitor",
                    logger: Logger.pluginLifecycle)
        self?.startActivationMonitor()
      }
    }
  }

  func stop() {
    Task { @MainActor in
      self.dismissOverlay()
      self.stopActivationMonitor()
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
    activationMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return }
      let required: NSEvent.ModifierFlags = [.command, .shift]
      let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
      let pressed = event.modifierFlags.intersection(relevantFlags)
      if event.keyCode == 49 {
        Logger.debug(
          "KeyboardPlugin saw Space — modifiers: \(pressed.rawValue), required: \(required.rawValue)",
          logger: Logger.pluginLifecycle
        )
      }
      guard event.keyCode == 49, pressed == required else { return }
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
        return
      }
      let sorted = elements.sorted { lhs, rhs in
        if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
        return lhs.screenFrame.minX < rhs.screenFrame.minX
      }
      let labeled = LabelGenerator.label(sorted)
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
    []
  }

  func menuWidgets() -> [MenuWidget] {
    [
      MenuWidget(id: "\(id).detail", pluginId: id, name: "Jump Navigation", priority: 50) {
        HStack {
          Image(systemName: "keyboard")
            .foregroundColor(.secondary)
          Text("Jump Navigation")
          Spacer()
          Text("⌘⇧Space")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
      }
    ]
  }
}
