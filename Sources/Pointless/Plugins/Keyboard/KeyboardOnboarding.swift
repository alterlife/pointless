import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Input Monitoring check
//
// CGPreflightListenEventAccess() (available since macOS 10.15) is the correct API
// but is not consistently exported by the Swift module in SPM builds. We link
// directly to the C symbol using @_silgen_name, which resolves at link time against
// CoreGraphics.framework where the symbol always exists.

@_silgen_name("CGPreflightListenEventAccess")
private func cgPreflightListenEventAccess() -> Bool

private func checkInputMonitoringAccess() -> Bool {
  cgPreflightListenEventAccess()
}

// MARK: - Controller

@MainActor
final class KeyboardOnboardingController: ObservableObject {
  static let shared = KeyboardOnboardingController()

  @Published private(set) var hasAccessibility: Bool
  @Published private(set) var hasInputMonitoring: Bool
  @Published private(set) var showSuccess: Bool = false

  var allGranted: Bool { hasAccessibility && hasInputMonitoring }

  private var window: NSWindow?
  private var pollTimer: Timer?

  private init() {
    hasAccessibility = AXIsProcessTrusted()
    hasInputMonitoring = checkInputMonitoringAccess()
  }

  func showIfNeeded(onComplete: @escaping () -> Void) {
    refresh()
    if allGranted {
      onComplete()
      return
    }
    showWindow()
    startPolling(onComplete: onComplete)
  }

  func refresh() {
    hasAccessibility = AXIsProcessTrusted()
    hasInputMonitoring = checkInputMonitoringAccess()
  }

  private func startPolling(onComplete: @escaping () -> Void) {
    stopPolling()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refresh()
        guard self.allGranted else { return }
        self.stopPolling()
        self.showSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          self?.showSuccess = false
          self?.window?.orderOut(nil)
          onComplete()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
  }

  private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private func showWindow() {
    if let existing = window, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    win.title = "Jump Navigation Setup"
    win.contentView = NSHostingView(rootView: OnboardingView(controller: self))
    win.center()
    win.isReleasedWhenClosed = false
    window = win
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

// MARK: - Permission row model

private struct PermissionInfo {
  let step: Int
  let symbol: String
  let title: String
  let description: String
  let settingsPath: String
}

// MARK: - View

struct OnboardingView: View {
  @ObservedObject var controller: KeyboardOnboardingController

  private let permissions: [PermissionInfo] = [
    PermissionInfo(
      step: 1, symbol: "accessibility", title: "Accessibility",
      description: "Reads UI elements so jump targets can be found",
      settingsPath: "Privacy_Accessibility"
    ),
    PermissionInfo(
      step: 2, symbol: "keyboard", title: "Input Monitoring",
      description: "Intercepts the activation shortcut and navigation keys",
      settingsPath: "Privacy_InputMonitoring"
    )
  ]

  var body: some View {
    VStack(spacing: 0) {
      headerView
      Divider()
      VStack(spacing: 16) {
        permissionRow(permissions[0], isGranted: controller.hasAccessibility)
        permissionRow(permissions[1], isGranted: controller.hasInputMonitoring)
        if controller.showSuccess {
          successBanner
        } else {
          footerHint
        }
      }
      .padding(24)
    }
  }

  private var headerView: some View {
    HStack(spacing: 12) {
      Image(systemName: "keyboard")
        .font(.system(size: 28, weight: .light))
        .foregroundColor(.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Jump Navigation")
          .font(.headline)
        Text("Grant two permissions to enable jump-to-click navigation")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(20)
  }

  @ViewBuilder
  private func permissionRow(_ info: PermissionInfo, isGranted: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(isGranted ? Color.accentColor : Color.secondary.opacity(0.15))
          .frame(width: 32, height: 32)
        if isGranted {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
        } else {
          Text("\(info.step)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.secondary)
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Image(systemName: info.symbol)
            .font(.system(size: 13))
            .foregroundColor(isGranted ? .accentColor : .secondary)
          Text(info.title)
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          if isGranted {
            Text("Granted")
              .font(.caption)
              .foregroundColor(.green)
          }
        }
        Text(info.description)
          .font(.caption)
          .foregroundColor(.secondary)
        if !isGranted {
          Button("Open System Settings →") {
            openSettings(path: info.settingsPath)
          }
          .buttonStyle(.link)
          .font(.caption)
          .padding(.top, 2)
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isGranted ? Color.accentColor.opacity(0.05) : Color(NSColor.controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(isGranted ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
    )
    .animation(.easeInOut(duration: 0.25), value: isGranted)
  }

  private var successBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
      Text("All set! Activating Jump Navigation…")
        .font(.system(size: 13, weight: .medium))
    }
    .frame(maxWidth: .infinity)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.3)))
    .transition(.opacity.combined(with: .scale(scale: 0.97)))
  }

  private var footerHint: some View {
    Text("Status updates automatically as you grant permissions in System Settings")
      .font(.caption)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
  }

  private func openSettings(path: String) {
    let base = "x-apple.systempreferences:com.apple.preference.security?"
    guard let url = URL(string: base + path) else { return }
    NSWorkspace.shared.open(url)
  }
}
