import AppKit
import SwiftUI

// MARK: - Empty-scan hint

@MainActor
func showEmptyHint() {
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
    Text("No interactive elements found")
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .foregroundColor(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(Capsule().fill(Color.black.opacity(0.7)))
  )
  win.contentView = label
  win.center()
  win.makeKeyAndOrderFront(nil)

  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.3
      win.animator().alphaValue = 0
    } completionHandler: {
      win.orderOut(nil)
    }
  }
}

// MARK: - CGRect helpers

extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
  init(center: CGPoint, size: CGSize) {
    self.init(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}

// MARK: - Coordinate utilities (internal for testability)

/// Anchor point in SwiftUI canvas coords (top-left origin) for a discovered element
internal func anchorPoint(screenFrame: CGRect, screenRect: CGRect) -> CGPoint {
  CGPoint(
    x: screenFrame.minX - screenRect.minX + 4,
    y: screenRect.maxY - screenFrame.maxY + 4
  )
}

/// Badge origin (top-left) — prefers above-left of anchor, falls back below if near screen top
internal func badgeOrigin(anchor: CGPoint, badgeSize: CGSize, viewSize: CGSize) -> CGPoint {
  let preferredY = anchor.y - badgeSize.height - 6
  let finalY = preferredY < 8 ? anchor.y + 10 : preferredY
  let rawX = anchor.x - badgeSize.width - 4
  let finalX = max(4, min(rawX, viewSize.width - badgeSize.width - 4))
  return CGPoint(x: finalX, y: finalY)
}

// MARK: - Overlay state

final class OverlayState: ObservableObject {
  @Published var labeledElements: [LabeledElement] = []
  @Published var typedPrefix: String = ""
  @Published var scrollTargetFrame: CGRect?

  var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  var textColor = Color.black
  var badgeFontSize: CGFloat = 11
  var showConnectorLines = true
  var fadeInDuration = 0.08

  var filteredElements: [LabeledElement] {
    LabelGenerator.filter(labeledElements, prefix: typedPrefix)
  }
}

// MARK: - Overlay window

final class ElementOverlayWindow: NSWindow {
  init(screen: NSScreen, state: OverlayState) {
    super.init(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    level = .popUpMenu
    ignoresMouseEvents = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let view = OverlayContentView(state: state, screen: screen)
    contentView = NSHostingView(rootView: view)
    setFrame(screen.frame, display: false)
  }

  func show(fadeDuration: Double) {
    alphaValue = 0
    orderFront(nil)
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = fadeDuration
      animator().alphaValue = 1
    }
  }

  func hide() {
    orderOut(nil)
  }
}

// MARK: - Canvas content view

struct OverlayContentView: View {
  @ObservedObject var state: OverlayState
  let screen: NSScreen

  var body: some View {
    ZStack(alignment: .top) {
      Canvas { ctx, size in
        var placedBadges: [CGRect] = []
        for labeled in state.labeledElements {
          drawElement(labeled, in: &ctx, viewSize: size, placedBadges: &placedBadges)
        }
        if let target = state.scrollTargetFrame {
          drawScrollTarget(target, in: &ctx)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      escHint
        .padding(.top, 8)
    }
  }

  private var escHint: some View {
    let text = state.scrollTargetFrame != nil
      ? "j/k scroll  ·  d/u half page  ·  ⌘⇧J next  ·  ⌘⇧K prev  ·  ESC exit"
      : "type a letter to jump  ·  ⌫ back  ·  ESC cancel"
    return Text(text)
      .font(.system(size: 11, weight: .medium, design: .rounded))
      .foregroundColor(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color.black.opacity(0.55)))
  }

  private func drawElement(
    _ labeled: LabeledElement,
    in context: inout GraphicsContext,
    viewSize: CGSize,
    placedBadges: inout [CGRect]
  ) {
    let anchor = anchorPoint(screenFrame: labeled.element.screenFrame, screenRect: screen.frame)
    let upperLabel = labeled.label.uppercased()
    let badgeSize = measureBadge(label: upperLabel, context: context)
    let origin = badgeOrigin(anchor: anchor, badgeSize: badgeSize, viewSize: viewSize)
    var badgeRect = CGRect(origin: origin, size: badgeSize)
    // Nested/adjacent elements can anchor at nearly the same corner — nudge the badge
    // down until it no longer covers an already-placed one, so labels never stack.
    var nudges = 0
    while nudges < 8, placedBadges.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(badgeRect) }) {
      badgeRect.origin.y += badgeSize.height + 3
      nudges += 1
    }
    placedBadges.append(badgeRect)

    let dimmed = !state.typedPrefix.isEmpty && !labeled.label.hasPrefix(state.typedPrefix)
    let alpha: Double = dimmed ? 0.2 : 1.0
    let fillColor = state.badgeColor.opacity(alpha)

    drawConnector(anchor: anchor, center: badgeRect.center, alpha: alpha, context: &context)
    drawDot(at: anchor, color: fillColor, context: &context)
    drawBadge(rect: badgeRect, color: fillColor, label: upperLabel, alpha: alpha, context: &context)
  }

  private func measureBadge(label: String, context: GraphicsContext) -> CGSize {
    let text = Text(label)
      .font(.system(size: state.badgeFontSize, weight: .bold, design: .monospaced))
    let resolved = context.resolve(text)
    let measured = resolved.measure(in: CGSize(width: 100, height: 50))
    return CGSize(width: measured.width + 8, height: measured.height + 4)
  }

  private func drawConnector(
    anchor: CGPoint,
    center: CGPoint,
    alpha: Double,
    context: inout GraphicsContext
  ) {
    guard state.showConnectorLines else { return }
    var path = Path()
    path.move(to: anchor)
    path.addLine(to: center)
    context.stroke(path, with: .color(state.badgeColor.opacity(alpha * 0.6)), lineWidth: 1.5)
  }

  private func drawDot(at anchor: CGPoint, color: Color, context: inout GraphicsContext) {
    let dotRect = CGRect(center: anchor, size: CGSize(width: 6, height: 6))
    context.fill(Path(ellipseIn: dotRect), with: .color(color))
  }

  private func drawBadge(
    rect: CGRect,
    color: Color,
    label: String,
    alpha: Double,
    context: inout GraphicsContext
  ) {
    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color))
    let textView = Text(label)
      .font(.system(size: state.badgeFontSize, weight: .bold, design: .monospaced))
      .foregroundColor(state.textColor.opacity(alpha))
    context.draw(textView, at: rect.center)
  }

  private func drawScrollTarget(_ frame: CGRect, in context: inout GraphicsContext) {
    let canvasRect = CGRect(
      x: frame.minX - screen.frame.minX,
      y: screen.frame.maxY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
    let path = Path(roundedRect: canvasRect.insetBy(dx: 2, dy: 2), cornerRadius: 6)
    context.fill(path, with: .color(state.badgeColor.opacity(0.08)))
    context.stroke(path, with: .color(state.badgeColor), lineWidth: 2.5)
  }
}
