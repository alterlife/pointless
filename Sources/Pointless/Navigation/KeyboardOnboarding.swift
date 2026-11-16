import AppKit
import ApplicationServices
import OSLog
import SwiftUI

// MARK: - Controller

@MainActor
final class KeyboardOnboardingController: ObservableObject {
  static let shared = KeyboardOnboardingController()

  @Published private(set) var hasAccessibility: Bool
  @Published private(set) var showSuccess: Bool = false

  var allGranted: Bool { hasAccessibility }

  /// Whether onComplete has been called (activation monitor installed)
  private(set) var isActivated = false

  private var window: NSWindow?
  private var pollTimer: Timer?
  private var pendingCompletion: (() -> Void)?

  private init() {
    hasAccessibility = AXIsProcessTrusted()
  }

  func showIfNeeded(onComplete: @escaping () -> Void) {
    // Trigger system permission prompts on first launch
    if !hasAccessibility {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }
    refresh()
    Logger.info(
      "KeyboardOnboarding: AX=\(hasAccessibility), allGranted=\(allGranted)",
      logger: Logger.pluginLifecycle
    )
    if allGranted {
      isActivated = true
      onComplete()
      return
    }
    pendingCompletion = onComplete
    showWindow()
    startPolling()
  }

  /// Re-check permissions and show onboarding if still needed.
  /// Called when user tries to activate but permissions aren't granted yet.
  func ensurePermissions() {
    refresh()
    guard !allGranted else { return }
    showWindow()
    if pollTimer == nil {
      startPolling()
    }
  }

  func refresh() {
    hasAccessibility = AXIsProcessTrusted()
  }

  func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func startPolling() {
    stopPolling()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refresh()
        guard self.allGranted else { return }
        self.stopPolling()
        self.showSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          guard let self else { return }
          self.showSuccess = false
          self.window?.orderOut(nil)
          NSApp.setActivationPolicy(.accessory)
          if !self.isActivated, let completion = self.pendingCompletion {
            self.isActivated = true
            self.pendingCompletion = nil
            completion()
          }
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
    win.level = .floating
    win.collectionBehavior = [.moveToActiveSpace, .transient]
    window = win
    win.makeKeyAndOrderFront(nil)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

// MARK: - View

struct OnboardingView: View {
  @ObservedObject var controller: KeyboardOnboardingController

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "keyboard")
        .font(.system(size: 40, weight: .light))
        .foregroundColor(.accentColor)
      VStack(spacing: 6) {
        Text("Pointless needs Accessibility access")
          .font(.headline)
        Text("It reads the UI elements on screen to find click targets, " +
          "and captures the navigation shortcut. macOS will ask you to approve it.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      if controller.showSuccess {
        Label("All set!", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
      } else {
        Button {
          controller.requestAccessibility()
        } label: {
          HStack {
            Image(systemName: controller.hasAccessibility ? "checkmark.circle.fill" : "circle")
              .foregroundColor(controller.hasAccessibility ? .green : .secondary)
            Text("Accessibility")
            Spacer()
            Text(controller.hasAccessibility ? "Granted" : "Request")
              .foregroundColor(.secondary)
          }
          .frame(width: 220)
        }
        .buttonStyle(.bordered)
        .disabled(controller.hasAccessibility)
        if !controller.hasAccessibility {
          Text("Waiting for approval in System Settings")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .padding(28)
    .frame(width: 400)
  }
}
