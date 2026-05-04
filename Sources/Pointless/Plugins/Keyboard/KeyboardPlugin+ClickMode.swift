import AppKit
import CoreGraphics
import OSLog

// MARK: - CGEventTap free function (C callback — must be top-level)

func keyboardPluginEventCallback(
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

// MARK: - Click Mode

extension KeyboardPlugin {
  @MainActor
  func handleActivation() {
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
      let sorted = elements.sortedByPosition()
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

  func rebuildOverlayWindows() {
    overlayWindows.forEach { $0.hide() }
    overlayWindows = NSScreen.screens.map { ElementOverlayWindow(screen: $0, state: overlayState) }
  }

  func startNavigationMonitor() {
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

  func stopNavigationMonitor() {
    guard let tap = eventTap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    eventTap = nil
  }
}
