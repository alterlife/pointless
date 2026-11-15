import AppKit
import CoreGraphics
import OSLog

// MARK: - CGEventTap free function (C callback — must be top-level)

private func navigationSessionEventCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent?,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let event else { return nil }
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let session = Unmanaged<NavigationSession>.fromOpaque(userInfo).takeUnretainedValue()

  if type == .leftMouseDown || type == .rightMouseDown {
    Task { @MainActor in session.end() }
    return Unmanaged.passUnretained(event)
  }

  if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
    Task { @MainActor in session.handleKey(nsEvent) }
    return nil
  }

  if type == .flagsChanged, let nsEvent = NSEvent(cgEvent: event) {
    Task { @MainActor in session.handleFlagsChanged(nsEvent) }
    return Unmanaged.passUnretained(event)
  }

  return Unmanaged.passUnretained(event)
}

// MARK: - NavigationSession

@MainActor
final class NavigationSession {
  enum Mode {
    case scanning
    case click(typedSoFar: String)
    case scrolling(targets: [NavigationTarget], currentIndex: Int)
  }

  struct Config {
    let fadeInDuration: Double
    let scrollSpeed: Double
    let labelStrategy: LabelGenerator.LabelStrategy
    let scrollNext: ParsedShortcut
    let scrollPrev: ParsedShortcut
  }

  var mode: Mode = .scanning

  let overlayState: OverlayState
  let config: Config
  private let onScanCompleted: (Int) -> Void
  private let onJump: () -> Void
  private let onEnded: () -> Void

  private let discovery = ElementDiscovery()
  private var overlayWindows: [ElementOverlayWindow] = []
  private var labeledElements: [LabeledElement] = []
  private var badgesShown = false
  var scrollHintWorkItem: DispatchWorkItem?
  private var clickHintWorkItem: DispatchWorkItem?
  var scrollOutlineWorkItem: DispatchWorkItem?
  var scrollDrainTimer: Timer?
  var pendingScroll: Int32 = 0
  var scrollGestureActive = false

  private static let clickHintKey = "navigation.clickHintDismissed"
  private static let clickHintDuration: Double = 5
  private var eventTap: CFMachPort?
  private var ended = false

  init(
    overlayState: OverlayState,
    config: Config,
    onScanCompleted: @escaping (Int) -> Void,
    onJump: @escaping () -> Void,
    onEnded: @escaping () -> Void
  ) {
    self.overlayState = overlayState
    self.config = config
    self.onScanCompleted = onScanCompleted
    self.onJump = onJump
    self.onEnded = onEnded
  }

  // MARK: - Click mode

  func beginClick() {
    rebuildOverlayWindows()
    badgesShown = false
    overlayState.clickHintDismissed = UserDefaults.standard.bool(forKey: Self.clickHintKey)
    clickHintWorkItem?.cancel()
    if !overlayState.clickHintDismissed {
      let work = DispatchWorkItem { [weak self] in
        self?.overlayState.clickHintDismissed = true
      }
      clickHintWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickHintDuration, execute: work)
    }
    discovery.scan(onProgress: { [weak self] elements in
      self?.showProgress(elements)
    }, completion: { [weak self] elements in
      guard let self, !self.ended else { return }
      guard !elements.isEmpty else {
        Logger.warning("No interactive elements found in focused window", logger: Logger.pluginLifecycle)
        self.end()
        showEmptyHint()
        return
      }
      self.applySnapshot(elements)
      self.showBadges()
      self.mode = .click(typedSoFar: "")
      self.installEventTap()
      let groupDesc = self.overlayState.collapsedGroups.map {
        "\($0.label)@\(Int($0.frame.minX)),\(Int($0.frame.minY))"
      }.joined(separator: " ")
      Logger.debug(
        "Labels: \(self.labeledElements.count) elements, groups=\(groupDesc)",
        logger: Logger.pluginLifecycle
      )
      let targetDesc = self.labeledElements.map {
        "\($0.label):\($0.element.role)@\(Int($0.element.screenFrame.minX)),\(Int($0.element.screenFrame.minY))"
      }.joined(separator: " ")
      Logger.debug("Targets: \(targetDesc)", logger: Logger.pluginLifecycle)
      self.onScanCompleted(elements.count)
    })
  }

  /// Early pass results render immediately, but keys stay locked until the
  /// final snapshot — labels can still shift as later passes add elements.
  private func showProgress(_ elements: [NavigationTarget]) {
    guard !ended, !elements.isEmpty else { return }
    applySnapshot(elements)
    showBadges()
  }

  private func applySnapshot(_ elements: [NavigationTarget]) {
    let labeled = LabelGenerator.label(
      elements.sortedByPosition(), strategy: config.labelStrategy
    )
    labeledElements = labeled
    overlayState.labeledElements = labeled
    overlayState.collapsedGroups = LabelGenerator.collapsedGroups(in: labeled)
    overlayState.typedPrefix = ""
  }

  private func showBadges() {
    guard !badgesShown else { return }
    badgesShown = true
    overlayWindows.forEach { $0.show(fadeDuration: config.fadeInDuration) }
  }

  // MARK: - Scroll mode

  func beginScroll() {
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
      self.installEventTap()
      self.scheduleScrollHint()
    }
  }

  // MARK: - Key handling

  func handleKey(_ event: NSEvent) {
    switch mode {
    case .click(let prefix):
      handleClickKey(event, prefix: prefix)
    case .scrolling(let targets, let currentIndex):
      handleScrollKey(event, targets: targets, currentIndex: currentIndex)
    case .scanning:
      break
    }
  }

  func handleFlagsChanged(_ event: NSEvent) {
    overlayState.revealElementText = event.modifierFlags.contains(.command)
  }

  private func handleClickKey(_ event: NSEvent, prefix: String) {
    switch event.keyCode {
    case 53:  // ESC
      end()
    case 51:  // Backspace
      updatePrefix(String(prefix.dropLast()))
    default:
      guard let char = event.charactersIgnoringModifiers?.lowercased().first,
            LabelGenerator.priorityKeys.contains(char) else { return }
      let newPrefix = prefix + String(char)
      if let match = LabelGenerator.exactMatch(in: labeledElements, for: newPrefix) {
        activate(match)
      } else if LabelGenerator.filter(labeledElements, prefix: newPrefix).isEmpty {
        end()
      } else {
        updatePrefix(newPrefix)
      }
    }
  }

  private func handleScrollKey(_ event: NSEvent, targets: [NavigationTarget], currentIndex: Int) {
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

  private func updatePrefix(_ prefix: String) {
    mode = .click(typedSoFar: prefix)
    overlayState.typedPrefix = prefix
    overlayState.clickHintDismissed = true
  }

  // MARK: - Element activation

  private func activate(_ labeled: LabeledElement) {
    UserDefaults.standard.set(true, forKey: Self.clickHintKey)
    let element = labeled.element.element
    let center = labeled.element.screenFrame.center
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let clickPoint = CGPoint(x: center.x, y: primaryHeight - center.y)
    onJump()
    end()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      self.warpCursor(to: labeled.element)
      // AXPress beats a synthetic click — some apps ignore clicks at frame centers.
      if element.performPress() { return }
      Self.postClick(at: Self.unobscuredClickPoint(for: labeled.element) ?? clickPoint)
    }
  }

  private static func unobscuredClickPoint(for discovered: NavigationTarget) -> CGPoint? {
    guard let app = AXElement.frontmostApplication() else { return nil }
    let frame = discovered.screenFrame
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let candidates: [(CGFloat, CGFloat)] = [
      (0.5, 0.5), (0.5, 0.3), (0.5, 0.7), (0.3, 0.5), (0.7, 0.5),
      (0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)
    ]
    var centerPoint: CGPoint?
    for (xFraction, yFraction) in candidates {
      // AX hit-test and CGEvent both take top-left-origin global coords.
      let point = CGPoint(
        x: frame.minX + frame.width * xFraction,
        y: primaryHeight - (frame.minY + frame.height * yFraction)
      )
      if centerPoint == nil { centerPoint = point }
      guard let hit = app.elementAt(axX: point.x, axY: point.y) else { continue }
      if hit.isSameElement(as: discovered.element) || hit.isDescendant(of: discovered.element) {
        return point
      }
    }
    return centerPoint
  }

  private static func postClick(at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
  }

  // MARK: - Overlay windows

  private func rebuildOverlayWindows() {
    overlayWindows.forEach { $0.hide() }
    let screens = NSScreen.screens
    let screenFrames = screens.map(\.frame)
    overlayWindows = screens.map {
      ElementOverlayWindow(screen: $0, allScreenFrames: screenFrames, state: overlayState)
    }
  }

  // MARK: - Event tap

  private func installEventTap() {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                          | (1 << CGEventType.flagsChanged.rawValue)
                          | (1 << CGEventType.leftMouseDown.rawValue)
                          | (1 << CGEventType.rightMouseDown.rawValue)
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: navigationSessionEventCallback,
      userInfo: selfPtr
    ) else {
      Logger.error("Failed to create CGEventTap — Input Monitoring permission may be missing")
      end()
      return
    }
    eventTap = tap
    if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func removeEventTap() {
    guard let tap = eventTap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    eventTap = nil
  }

  // MARK: - Teardown

  func end() {
    guard !ended else { return }
    ended = true
    discovery.cancel()
    removeEventTap()
    overlayWindows.forEach { $0.hide() }
    overlayWindows = []
    overlayState.labeledElements = []
    overlayState.collapsedGroups = []
    overlayState.typedPrefix = ""
    overlayState.revealElementText = false
    overlayState.scrollTargetFrame = nil
    overlayState.showScrollHint = false
    overlayState.scrollOutlineHidden = false
    scrollHintWorkItem?.cancel()
    clickHintWorkItem?.cancel()
    scrollOutlineWorkItem?.cancel()
    finishScrollGesture()
    onEnded()
  }
}
