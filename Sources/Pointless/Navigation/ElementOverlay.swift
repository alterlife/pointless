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

/// Frame of the screen that draws an element's badge — the one holding its
/// anchor, else the first it overlaps. Keeps each badge on exactly one overlay.
internal func badgeScreen(for elementFrame: CGRect, among screenFrames: [CGRect]) -> CGRect? {
  let anchor = CGPoint(x: elementFrame.minX + 4, y: elementFrame.maxY - 4)
  return screenFrames.first { $0.contains(anchor) }
    ?? screenFrames.first { $0.intersects(elementFrame) }
}

struct BadgeObstacles {
  var anchorRects: [CGRect] = []
  var placedBadges: [CGRect] = []
}

internal func placeBadges(
  anchors: [CGPoint], badgeSizes: [CGSize], viewSize: CGSize, topInset: CGFloat = 0
) -> [CGRect] {
  var obstacles = BadgeObstacles(
    anchorRects: anchors.map { CGRect(center: $0, size: CGSize(width: 8, height: 8)) }
  )
  return anchors.indices.map { index in
    let rect = placeBadge(
      anchor: anchors[index], badgeSize: badgeSizes[index], viewSize: viewSize,
      obstacles: obstacles, ownAnchorIndex: index, topInset: topInset
    )
    obstacles.placedBadges.append(rect)
    return rect
  }
}

internal func placeBadge(
  anchor: CGPoint,
  badgeSize: CGSize,
  viewSize: CGSize,
  obstacles: BadgeObstacles,
  ownAnchorIndex: Int,
  topInset: CGFloat = 0
) -> CGRect {
  let candidates = [
    CGPoint(x: anchor.x - badgeSize.width - 4, y: anchor.y - badgeSize.height - 6),
    CGPoint(x: anchor.x + 4, y: anchor.y - badgeSize.height - 6),
    CGPoint(x: anchor.x - badgeSize.width - 4, y: anchor.y + 10),
    CGPoint(x: anchor.x + 4, y: anchor.y + 10)
  ]

  func clamped(_ origin: CGPoint) -> CGPoint {
    CGPoint(
      x: max(4, min(origin.x, viewSize.width - badgeSize.width - 4)),
      y: max(topInset + 4, min(origin.y, viewSize.height - badgeSize.height - 4))
    )
  }

  func collides(_ rect: CGRect) -> Bool {
    let hitsAnchor = obstacles.anchorRects.enumerated().contains { index, anchorRect in
      index != ownAnchorIndex && anchorRect.intersects(rect)
    }
    let hitsBadge = obstacles.placedBadges.contains { $0.insetBy(dx: -2, dy: -2).intersects(rect) }
    return hitsAnchor || hitsBadge
  }

  for candidate in candidates {
    let rect = CGRect(origin: clamped(candidate), size: badgeSize)
    if !collides(rect) { return rect }
  }

  var rect = CGRect(origin: clamped(candidates[0]), size: badgeSize)
  var nudges = 0
  while nudges < 8, collides(rect) {
    rect.origin.y = min(rect.origin.y + badgeSize.height + 3,
                        max(4, viewSize.height - badgeSize.height - 4))
    nudges += 1
  }
  return rect
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
  init(screen: NSScreen, allScreenFrames: [CGRect], state: OverlayState) {
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

    let view = OverlayContentView(state: state, screen: screen, allScreenFrames: allScreenFrames)
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
  let allScreenFrames: [CGRect]

  var body: some View {
    ZStack(alignment: .top) {
      Canvas { ctx, size in
        let onScreen = state.labeledElements.filter {
          badgeScreen(for: $0.element.screenFrame, among: allScreenFrames) == screen.frame
        }
        let anchors = onScreen.map {
          anchorPoint(screenFrame: $0.element.screenFrame, screenRect: screen.frame)
        }
        let badgeSizes = onScreen.map {
          measureBadge(label: $0.label, context: ctx)
        }
        let badgeRects = placeBadges(
          anchors: anchors, badgeSizes: badgeSizes, viewSize: size,
          topInset: screen.safeAreaInsets.top
        )
        for (index, labeled) in onScreen.enumerated() {
          drawElement(labeled, badgeRect: badgeRects[index], anchor: anchors[index], in: &ctx)
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
    badgeRect: CGRect,
    anchor: CGPoint,
    in context: inout GraphicsContext
  ) {
    let dimmed = !state.typedPrefix.isEmpty && !labeled.label.hasPrefix(state.typedPrefix)
    let alpha: Double = dimmed ? 0.2 : 1.0
    let fillColor = state.badgeColor.opacity(alpha)

    drawConnector(anchor: anchor, center: badgeRect.center, alpha: alpha, context: &context)
    drawDot(at: anchor, color: fillColor, context: &context)
    drawBadge(rect: badgeRect, color: fillColor, label: labeled.label, alpha: alpha, context: &context)
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
