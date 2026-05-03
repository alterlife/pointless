import AppKit
import CoreGraphics
import OSLog

// MARK: - Scroll Mode

extension KeyboardPlugin {
  private enum ScrollDirection { case next, prev }

  // MARK: Monitors

  func startScrollMonitors() {
    let nextCode = scrollNextCode
    let nextMods = scrollNextMods
    scrollNextMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return }
      let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
      let pressed = event.modifierFlags.intersection(relevantFlags)
      guard event.keyCode == nextCode, pressed == nextMods else { return }
      Task { @MainActor in self.handleScrollActivation(.next) }
    }
    let prevCode = scrollPrevCode
    let prevMods = scrollPrevMods
    scrollPrevMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return }
      let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
      let pressed = event.modifierFlags.intersection(relevantFlags)
      guard event.keyCode == prevCode, pressed == prevMods else { return }
      Task { @MainActor in self.handleScrollActivation(.prev) }
    }
  }

  func stopScrollMonitors() {
    if let monitor = scrollNextMonitor {
      NSEvent.removeMonitor(monitor)
      scrollNextMonitor = nil
    }
    if let monitor = scrollPrevMonitor {
      NSEvent.removeMonitor(monitor)
      scrollPrevMonitor = nil
    }
  }

  // MARK: Activation

  @MainActor
  private func handleScrollActivation(_ direction: ScrollDirection) {
    let onboarding = KeyboardOnboardingController.shared
    onboarding.refresh()
    guard onboarding.allGranted else {
      onboarding.ensurePermissions()
      return
    }

    // If already scrolling, NSEvent monitor does nothing — CGEventTap handles cycling
    if case .scrolling = phase { return }
    // Only activate from inactive state; ignore if click overlay is up
    guard case .inactive = phase else { return }

    phase = .scanning
    let scan = AccessibilityScanner()
    scanner = scan
    scan.scan(mode: .scrollable) { [weak self] elements in
      guard let self else { return }
      // Filter out scroll areas with broken frames (zero size or off-screen)
      let screenBounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
      let viable = elements.filter { elem in
        let frame = elem.screenFrame
        return frame.width >= 50 && frame.height >= 50 && screenBounds.intersects(frame)
      }
      guard !viable.isEmpty else {
        Logger.warning("No scrollable elements found in focused window", logger: Logger.pluginLifecycle)
        self.phase = .inactive
        return
      }
      let sorted = viable.sorted { lhs, rhs in
        if lhs.screenFrame.minY != rhs.screenFrame.minY { return lhs.screenFrame.minY > rhs.screenFrame.minY }
        return lhs.screenFrame.minX < rhs.screenFrame.minX
      }
      let mousePos = NSEvent.mouseLocation
      let startIndex = sorted.firstIndex { $0.screenFrame.contains(mousePos) } ?? 0
      self.rebuildOverlayWindows()
      // For multiple targets, warp cursor to selected area
      if sorted.count > 1 {
        self.warpCursorTo(sorted[startIndex])
      }
      self.overlayState.scrollTargetFrame = sorted[startIndex].screenFrame
      self.phase = .scrolling(targets: sorted, currentIndex: startIndex)
      self.overlayWindows.forEach { $0.show(fadeDuration: self.fadeInDuration) }
      self.startNavigationMonitor()
    }
  }

  // MARK: Key Handling

  @MainActor
  func handleScrollKey(_ event: NSEvent, targets: [DiscoveredElement], currentIndex: Int) {
    let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if event.keyCode == scrollNextCode, mods == scrollNextMods {
      cycleScrollTarget(targets: targets, from: currentIndex, direction: .next)
      return
    }
    if event.keyCode == scrollPrevCode, mods == scrollPrevMods {
      cycleScrollTarget(targets: targets, from: currentIndex, direction: .prev)
      return
    }
    switch event.keyCode {
    case 53:       // ESC
      exitScrollMode()
    case 38, 125:  // j / ↓ → scroll down
      synthesizeScroll(deltaY: -3)
    case 40, 126:  // k / ↑ → scroll up
      synthesizeScroll(deltaY: 3)
    default:
      exitScrollMode()
    }
  }

  @MainActor
  private func cycleScrollTarget(targets: [DiscoveredElement], from index: Int, direction: ScrollDirection) {
    guard !targets.isEmpty else { return }
    let count = targets.count
    let newIndex: Int
    switch direction {
    case .next: newIndex = (index + 1) % count
    case .prev: newIndex = (index - 1 + count) % count
    }
    warpCursorTo(targets[newIndex])
    overlayState.scrollTargetFrame = targets[newIndex].screenFrame
    phase = .scrolling(targets: targets, currentIndex: newIndex)
  }

  @MainActor
  private func synthesizeScroll(deltaY: Int32) {
    // Scroll events go to the current cursor position
    CGEvent(
      scrollWheelEvent2Source: nil, units: .line,
      wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0
    )?.post(tap: .cghidEventTap)
  }

  @MainActor
  private func warpCursorTo(_ element: DiscoveredElement) {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let cgPoint = CGPoint(x: element.screenFrame.midX, y: primaryHeight - element.screenFrame.midY)
    CGWarpMouseCursorPosition(cgPoint)
    CGAssociateMouseAndMouseCursorPosition(1)
  }

  @MainActor
  func exitScrollMode() {
    phase = .inactive
    overlayState.scrollTargetFrame = nil
    overlayWindows.forEach { $0.hide() }
    stopNavigationMonitor()
  }
}
