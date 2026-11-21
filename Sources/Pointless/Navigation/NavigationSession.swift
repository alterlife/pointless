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
  guard let userInfo else {
    return event.map { Unmanaged.passUnretained($0) }
  }
  let session = Unmanaged<NavigationSession>.fromOpaque(userInfo).takeUnretainedValue()

  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if Thread.isMainThread {
      MainActor.assumeIsolated { session.reEnableTap() }
    } else {
      DispatchQueue.main.async { session.reEnableTap() }
    }
    return event.map { Unmanaged.passUnretained($0) }
  }

  guard let event else { return nil }

  if type == .leftMouseDown || type == .rightMouseDown {
    if Thread.isMainThread {
      MainActor.assumeIsolated { session.end() }
    } else {
      DispatchQueue.main.async { session.end() }
    }
    return Unmanaged.passUnretained(event)
  }

  if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
    if Thread.isMainThread {
      MainActor.assumeIsolated { session.handleKey(nsEvent) }
    } else {
      DispatchQueue.main.async { session.handleKey(nsEvent) }
    }
    return nil
  }

  if type == .flagsChanged, let nsEvent = NSEvent(cgEvent: event) {
    if Thread.isMainThread {
      MainActor.assumeIsolated { session.handleFlagsChanged(nsEvent) }
    } else {
      DispatchQueue.main.async { session.handleFlagsChanged(nsEvent) }
    }
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
    let gridSwitchShortcut: ParsedShortcut
    let gridLetters: [Character]
    let gridMaxLevel: Int
    let gridAutoClick: Bool
  }

  var mode: Mode = .scanning

  let overlayState: OverlayState
  let config: Config
  private let onScanCompleted: (Int) -> Void
  let onJump: () -> Void
  private let onEnded: () -> Void

  let discovery = ElementDiscovery()
  var overlayWindows: [ElementOverlayWindow] = []
  private var labeledElements: [LabeledElement] = []
  private var badgesShown = false
  var scrollHintWorkItem: DispatchWorkItem?
  private var clickHintWorkItem: DispatchWorkItem?
  var scrollOutlineWorkItem: DispatchWorkItem?
  var scrollDrainTimer: Timer?
  var pendingScroll: Int32 = 0
  var scrollGestureActive = false

  static let clickHintKey = "navigation.clickHintDismissed"
  private static let clickHintDuration: Double = 5
  private var eventTap: CFMachPort?
  var ended = false

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
    mode = .scanning
    installEventTap()
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
      self.mode = .click(typedSoFar: "")
      if !self.gridRegions.isEmpty { return }
      if !self.bufferedKeyEvents.isEmpty {
        self.replayBufferedKeys()
        if self.ended { return }
      }
      self.showBadges()
      Logger.debug(
        "Labels: \(self.labeledElements.count) elements",
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
    if gridRegions.isEmpty {
      showBadges()
    }
  }

  private func applySnapshot(_ elements: [NavigationTarget]) {
    let labeled = LabelGenerator.label(
      elements.sortedByPosition(), strategy: config.labelStrategy
    )
    labeledElements = labeled
    overlayState.labeledElements = labeled
    overlayState.typedPrefix = bufferedPrefix
  }

  func showBadges() {
    guard !badgesShown else { return }
    badgesShown = true
    overlayWindows.forEach { $0.show(fadeDuration: config.fadeInDuration) }
  }

  // MARK: - Key handling

  private var bufferedKeyEvents: [NSEvent] = []

  func handleKey(_ event: NSEvent) {
    guard !ended else { return }
    switch mode {
    case .click(let prefix):
      handleClickKey(event, prefix: prefix)
    case .scrolling(let targets, let currentIndex):
      handleScrollKey(event, targets: targets, currentIndex: currentIndex)
    case .scanning:
      handleScanningKey(event)
    }
  }

  private func handleScanningKey(_ event: NSEvent) {
    if !gridRegions.isEmpty {
      handleZoneKey(event)
      return
    }
    if eventMatchesHotkey(event, shortcut: config.gridSwitchShortcut) {
      startGrid()
      return
    }
    switch event.keyCode {
    case 53:  // ESC
      end()
    case 51:  // Backspace
      if !bufferedKeyEvents.isEmpty {
        bufferedKeyEvents.removeLast()
        updateBufferedPrefix()
      }
    default:
      guard let char = event.charactersIgnoringModifiers?.lowercased().first,
            LabelGenerator.priorityKeys.contains(char) else { return }
      bufferedKeyEvents.append(event)
      updateBufferedPrefix()
    }
  }

  private func updateBufferedPrefix() {
    overlayState.typedPrefix = bufferedPrefix
  }

  private var bufferedPrefix: String {
    bufferedKeyEvents.compactMap {
      $0.charactersIgnoringModifiers?.lowercased().first
    }.map(String.init).joined()
  }

  private func replayBufferedKeys() {
    let events = bufferedKeyEvents
    bufferedKeyEvents = []
    for event in events {
      guard !ended else { break }
      handleKey(event)
    }
  }

  func handleFlagsChanged(_ event: NSEvent) {
    overlayState.revealElementText = event.modifierFlags.contains(.command)
  }

  var isDragArmed = false
  var gridRegions: [CGRect] = []
  var gridPath: [Character] = []

  private func handleClickKey(_ event: NSEvent, prefix: String) {
    if !gridRegions.isEmpty {
      handleZoneKey(event)
      return
    }
    if eventMatchesHotkey(event, shortcut: config.gridSwitchShortcut) {
      startGrid()
      return
    }
    switch event.keyCode {
    case 53:  // ESC
      end()
    case 51:  // Backspace
      updatePrefix(String(prefix.dropLast()))
    default:
      if handleCursorKey(event) { return }
      let controlHeld = event.modifierFlags.contains(.control)
      guard let char = event.charactersIgnoringModifiers?.lowercased().first,
            LabelGenerator.priorityKeys.contains(char) else { return }
      let newPrefix = prefix + String(char)
      if let match = LabelGenerator.exactMatch(in: labeledElements, for: newPrefix) {
        if controlHeld {
          cursorActivate(match)
        } else {
          activate(match)
        }
      } else if LabelGenerator.filter(labeledElements, prefix: newPrefix).isEmpty {
        end()
      } else {
        updatePrefix(newPrefix)
      }
    }
  }

  func updatePrefix(_ prefix: String) {
    mode = .click(typedSoFar: prefix)
    overlayState.typedPrefix = prefix
    overlayState.clickHintDismissed = true
  }

  // MARK: - Overlay windows

  func rebuildOverlayWindows() {
    overlayWindows.forEach { $0.hide() }
    let screens = NSScreen.screens
    let screenFrames = screens.map(\.frame)
    overlayWindows = screens.map {
      ElementOverlayWindow(screen: $0, allScreenFrames: screenFrames, state: overlayState)
    }
  }

  // MARK: - Event tap

  func installEventTap() {
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

  func reEnableTap() {
    guard let tap = eventTap else { return }
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
    bufferedKeyEvents = []
    discovery.cancel()
    removeEventTap()
    overlayWindows.forEach { $0.hide() }
    overlayWindows = []
    overlayState.labeledElements = []
    overlayState.gridRegion = nil
    overlayState.gridBreadcrumb = ""
    overlayState.gridPathPrefix = ""
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
