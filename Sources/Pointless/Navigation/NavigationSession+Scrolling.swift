import AppKit
import OSLog

extension NavigationSession {
  func beginScroll() {
    mode = .scanning
    installEventTap()
    discovery.scan(mode: .scrollable) { [weak self] elements in
      guard let self, !self.ended else { return }
      let screenBounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
      let viable = elements.filter { elem in
        let frame = elem.screenFrame
        return frame.width >= 50 && frame.height >= 50 && screenBounds.intersects(frame)
      }
      guard !viable.isEmpty else {
        Logger.warning("No scrollable elements found in focused window", logger: Logger.pluginLifecycle)
        self.end()
        showEmptyHint("No scrollable areas found")
        return
      }
      let byPosition = viable.sortedByPosition()
      let withScrollEvidence = byPosition.filter { $0.element.hasScrollIndicators }
      let withoutScrollEvidence = byPosition.filter { !$0.element.hasScrollIndicators }
      let sorted = withScrollEvidence + withoutScrollEvidence
      let mousePos = NSEvent.mouseLocation
      let startIndex = sorted.firstIndex { $0.screenFrame.contains(mousePos) } ?? 0
      self.rebuildOverlayWindows()
      if sorted.count > 1 {
        self.warpCursor(to: sorted[startIndex])
      }
      self.overlayState.scrollTargetFrame = sorted[startIndex].screenFrame
      self.mode = .scrolling(targets: sorted, currentIndex: startIndex)
      self.overlayWindows.forEach { $0.show(fadeDuration: self.config.fadeInDuration) }
      self.scheduleScrollHint()
    }
  }

  func handleScrollKey(_ event: NSEvent, targets: [NavigationTarget], currentIndex: Int) {
    scheduleScrollHint()
    if eventMatchesHotkey(event, keyCode: config.scrollNext.keyCode, modifiers: config.scrollNext.modifiers) {
      cycleScrollTarget(targets: targets, from: currentIndex, offset: 1)
      return
    }
    if eventMatchesHotkey(event, keyCode: config.scrollPrev.keyCode, modifiers: config.scrollPrev.modifiers) {
      cycleScrollTarget(targets: targets, from: currentIndex, offset: -1)
      return
    }
    switch event.keyCode {
    case 53:       // ESC
      end()
    case 38, 125:  // j / ↓ → scroll down
      enqueueScroll(deltaY: -Self.scrollStep)
    case 40, 126:  // k / ↑ → scroll up
      enqueueScroll(deltaY: Self.scrollStep)
    case 2:        // d → half page down
      enqueueScroll(deltaY: -Self.scrollPage)
    case 32:       // u → half page up
      enqueueScroll(deltaY: Self.scrollPage)
    default:
      end()
    }
  }

  static let scrollStep: Int32 = 60
  static let scrollPage: Int32 = 400
  private static let scrollHintDelay: Double = 3
  private static let maxPendingScroll: Int32 = 8000
  private static let drainInterval: Double = 1.0 / 120.0
  private static let maxDrainChunk: Int32 = 40
  private static let outlineResumeDelay: Double = 0.8

  func scheduleScrollHint() {
    scrollHintWorkItem?.cancel()
    overlayState.showScrollHint = false
    let work = DispatchWorkItem { [weak self] in
      guard let self, case .scrolling = self.mode else { return }
      self.overlayState.showScrollHint = true
    }
    scrollHintWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollHintDelay, execute: work)
  }

  func cycleScrollTarget(targets: [NavigationTarget], from index: Int, offset: Int) {
    guard !targets.isEmpty else { return }
    finishScrollGesture()
    let newIndex = (index + offset + targets.count) % targets.count
    warpCursor(to: targets[newIndex])
    overlayState.scrollTargetFrame = targets[newIndex].screenFrame
    overlayState.scrollOutlineHidden = false
    mode = .scrolling(targets: targets, currentIndex: newIndex)
    scheduleScrollHint()
  }

  /// Scroll keys enqueue distance; a drain timer posts it in small chunks so
  /// held-key repeats accelerate smoothly instead of jumping per keypress.
  func enqueueScroll(deltaY: Int32) {
    let scaled = Int32((Double(deltaY) * config.scrollSpeed).rounded())
    pendingScroll = max(-Self.maxPendingScroll, min(Self.maxPendingScroll, pendingScroll + scaled))
    startScrollDrain()
    hideScrollOutline()
  }

  private func startScrollDrain() {
    guard scrollDrainTimer == nil else { return }
    let timer = Timer(timeInterval: Self.drainInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.drainScroll() }
    }
    scrollDrainTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  /// Chunk size tracks the remainder — large queues drain fast, small ones
  /// taper off, which reads as glide rather than steps.
  private func drainScroll() {
    guard pendingScroll != 0 else {
      scrollDrainTimer?.invalidate()
      scrollDrainTimer = nil
      return
    }
    let magnitude = min(Self.maxDrainChunk, max(1, abs(pendingScroll) / 4))
    let chunk = pendingScroll > 0 ? magnitude : -magnitude
    let applied = abs(chunk) > abs(pendingScroll) ? pendingScroll : chunk
    let remaining = pendingScroll - applied
    // Bracket the burst as a scroll gesture: Began, Changed..., Ended.
    // Apps ignore phase events outside a gesture.
    let phase: Int32
    if !scrollGestureActive {
      phase = 1  // kCGScrollPhaseBegan
      scrollGestureActive = true
    } else if remaining == 0 {
      phase = 4  // kCGScrollPhaseEnded
      scrollGestureActive = false
    } else {
      phase = 2  // kCGScrollPhaseChanged
    }
    pendingScroll = remaining
    postScrollEvent(deltaY: applied, phase: phase)
  }

  /// Drops queued distance and closes an open gesture — the app needs the
  /// Ended phase or it waits on a scroll that will never finish.
  func finishScrollGesture() {
    scrollDrainTimer?.invalidate()
    scrollDrainTimer = nil
    pendingScroll = 0
    guard scrollGestureActive else { return }
    scrollGestureActive = false
    postScrollEvent(deltaY: 0, phase: 4)  // kCGScrollPhaseEnded
  }

  private func postScrollEvent(deltaY: Int32, phase: Int32) {
    // Pixel units scroll smoothly; line units jump in coarse steps.
    // isContinuous marks these as trackpad-style deltas, not wheel notches.
    guard let event = CGEvent(
      scrollWheelEvent2Source: nil, units: .pixel,
      wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0
    ) else { return }
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
    event.post(tap: .cghidEventTap)
  }

  private func hideScrollOutline() {
    overlayState.scrollOutlineHidden = true
    scrollOutlineWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.overlayState.scrollOutlineHidden = false
    }
    scrollOutlineWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.outlineResumeDelay, execute: work)
  }

  func warpCursor(to element: NavigationTarget) {
    let frame = element.screenFrame
    CGWarpMouseCursorPosition(cgPoint(fromAppKit: CGPoint(x: frame.midX, y: frame.midY)))
    CGAssociateMouseAndMouseCursorPosition(1)
  }
}
