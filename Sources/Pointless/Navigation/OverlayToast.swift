import AppKit
import SwiftUI

// MARK: - Empty-scan hint

@MainActor
func showEmptyHint(_ text: String = "No interactive elements found") {
  let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 36),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  win.backgroundColor = .clear
  win.isOpaque = false
  win.hasShadow = false
  win.level = .popUpMenu
  win.ignoresMouseEvents = true
  win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

  let label = NSHostingView(rootView:
    Text(text)
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .foregroundColor(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(Capsule().fill(Color.black.opacity(0.7)))
  )
  win.contentView = label
  win.center()
  win.orderFrontRegardless()

  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.3
      win.animator().alphaValue = 0
    } completionHandler: {
      win.orderOut(nil)
    }
  }
}

// MARK: - Spatial address toast

@MainActor
func showSpatialAddressToast(_ address: String, at point: CGPoint) {
  let width: CGFloat = 72 + CGFloat(address.count) * 8
  let height: CGFloat = 28
  let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
  let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
  let origin = NSPoint(
    x: max(bounds.minX + 8, min(point.x - width / 2, bounds.maxX - width - 8)),
    y: max(bounds.minY + 8, min(point.y + 16, bounds.maxY - height - 8))
  )
  let win = NSWindow(
    contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  win.backgroundColor = .clear
  win.isOpaque = false
  win.hasShadow = false
  win.level = .popUpMenu
  win.ignoresMouseEvents = true
  win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

  let view = NSHostingView(rootView:
    HStack(spacing: 4) {
      Text("📍")
        .font(.system(size: 10))
      Text(address)
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundColor(.black)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(Color(red: 0.95, green: 0.75, blue: 0.1)))
    .overlay(Capsule().stroke(Color.black.opacity(0.3), lineWidth: 1))
  )
  win.contentView = view
  win.orderFrontRegardless()

  DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.25
      win.animator().alphaValue = 0
    } completionHandler: {
      win.orderOut(nil)
    }
  }
}
