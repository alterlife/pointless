import Cocoa
import OSLog

/// CGEvent tap that consumes Pointless hotkeys so apps never see them.
/// Sits downstream of the session tap, which swallows all keys during a session.
@MainActor
final class HotkeyTap {
  enum Hotkey {
    case activate
    case scroll
  }

  private let activation: ParsedShortcut
  private let scrollNext: ParsedShortcut
  private let scrollPrev: ParsedShortcut
  private let shouldCapture: () -> Bool
  private let onHotkey: (Hotkey) -> Void
  private var tap: CFMachPort?

  init(
    activation: ParsedShortcut,
    scrollNext: ParsedShortcut,
    scrollPrev: ParsedShortcut,
    shouldCapture: @escaping () -> Bool,
    onHotkey: @escaping (Hotkey) -> Void
  ) {
    self.activation = activation
    self.scrollNext = scrollNext
    self.scrollPrev = scrollPrev
    self.shouldCapture = shouldCapture
    self.onHotkey = onHotkey
  }

  @discardableResult
  func start() -> Bool {
    guard tap == nil else { return true }
    let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let newTap = CGEvent.tapCreate(
      tap: .cgAnnotatedSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: hotkeyTapEventCallback,
      userInfo: selfPtr
    ) else {
      Logger.error("Failed to create hotkey event tap — Input Monitoring permission may be missing",
                   logger: Logger.pluginLifecycle)
      return false
    }
    tap = newTap
    if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    CGEvent.tapEnable(tap: newTap, enable: true)
    return true
  }

  func stop() {
    guard let tap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    self.tap = nil
  }

  fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return pass
    case .keyDown:
      guard shouldCapture(), let nsEvent = NSEvent(cgEvent: event) else { return pass }
      if eventMatchesHotkey(nsEvent, shortcut: activation) {
        onHotkey(.activate)
        return nil
      }
      if eventMatchesHotkey(nsEvent, shortcut: scrollNext)
          || eventMatchesHotkey(nsEvent, shortcut: scrollPrev) {
        onHotkey(.scroll)
        return nil
      }
      return pass
    default:
      return pass
    }
  }
}

// MARK: - CGEventTap free function (C callback — must be top-level)

private func hotkeyTapEventCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent?,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let event else { return nil }
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
  return MainActor.assumeIsolated {
    tap.handleEvent(type: type, event: event)
  }
}
