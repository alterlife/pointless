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

// MARK: - Badge alpha

func badgeAlpha(label: String, typedPrefix: String) -> Double {
  if !typedPrefix.isEmpty && !label.hasPrefix(typedPrefix) { return 0.2 }
  return 1.0
}

final class OverlayState: ObservableObject {
  @Published var labeledElements: [LabeledElement] = []
  @Published var typedPrefix: String = ""
  @Published var scrollTargetFrame: CGRect?
  @Published var scrollOutlineHidden = false
  @Published var showScrollHint = false
  @Published var clickHintDismissed = false
  @Published var revealElementText = false
  @Published var gridRegion: CGRect?

  var badgeColor = Color(red: 0.95, green: 0.75, blue: 0.1)
  var textColor = Color.black
  var badgeFontSize: CGFloat = 11
  var showConnectorLines = true
  var fadeInDuration = 0.08
  var gridModifierHint = "⌥"
  var gridLetters: [Character] = LabelGenerator.rightHandGridLetters

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

  private var hintVisible: Bool {
    if state.scrollTargetFrame != nil { return state.showScrollHint }
    return !state.clickHintDismissed
  }

  var body: some View {
    let hint = hintVisible && NSScreen.main === screen ? hintFrame() : nil
    return ZStack {
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
          topInset: screen.safeAreaInsets.top,
          reservedRects: hint.map { [$0.insetBy(dx: -4, dy: -4)] } ?? []
        )
        for labeled in onScreen where shouldHighlight(labeled) {
          drawHighlight(frame: labeled.element.screenFrame, in: &ctx)
        }
        for (index, labeled) in onScreen.enumerated() {
          drawElement(labeled, badgeRect: badgeRects[index], anchor: anchors[index], in: &ctx)
        }
        if let target = state.scrollTargetFrame, !state.scrollOutlineHidden {
          drawScrollTarget(target, in: &ctx)
        }
        if let region = state.gridRegion {
          drawGrid(region, in: &ctx)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if hint != nil {
        escHint
      }
    }
  }

  private var hintText: String {
    if state.gridRegion != nil {
      return "Space click  ·  Return right-click  ·  ⌫ back  ·  ESC cancel"
    }
    if state.scrollTargetFrame != nil {
      return "j/k scroll  ·  d/u half page  ·  ⌘⇧J next  ·  ⌘⇧K prev  ·  ESC exit"
    }
    return "type a letter to jump  ·  ⌫ back  ·  hold ⌘ highlight  ·  " +
           "hold ⌃ cursor  ·  hold \(state.gridModifierHint) grid  ·  ESC cancel"
  }

  private var hintSize: CGSize {
    let textSize = (hintText as NSString).size(
      withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
    )
    return CGSize(width: textSize.width + 32, height: textSize.height + 16)
  }

  private func hintFrame() -> CGRect {
    CGRect(
      x: (screen.frame.width - hintSize.width) / 2,
      y: (screen.frame.height - hintSize.height) / 2,
      width: hintSize.width,
      height: hintSize.height
    )
  }

  private var escHint: some View {
    Text(hintText)
      .font(.system(size: 13, weight: .semibold, design: .rounded))
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Capsule().fill(Color.black.opacity(0.8)))
  }

  private func drawElement(
    _ labeled: LabeledElement,
    badgeRect: CGRect,
    anchor: CGPoint,
    in context: inout GraphicsContext
  ) {
    let alpha = badgeAlpha(label: labeled.label, typedPrefix: state.typedPrefix)
    let fillColor = state.badgeColor.opacity(alpha)

    drawConnector(anchor: anchor, center: badgeRect.center, alpha: alpha, context: &context)
    drawDot(at: anchor, color: fillColor, context: &context)
    drawBadge(rect: badgeRect, color: fillColor, label: labeled.label, alpha: alpha, context: &context)
  }

  private func shouldHighlight(_ labeled: LabeledElement) -> Bool {
    guard state.revealElementText else { return false }
    return state.typedPrefix.isEmpty || labeled.label.hasPrefix(state.typedPrefix)
  }

  private func drawHighlight(frame: CGRect, in context: inout GraphicsContext) {
    let rect = CGRect(
      x: frame.minX - screen.frame.minX,
      y: screen.frame.maxY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
    context.stroke(
      Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 6),
      with: .color(Color(nsColor: .controlAccentColor).opacity(0.9)), lineWidth: 2.5
    )
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
    let badgePath = Path(roundedRect: rect, cornerRadius: 5)
    context.fill(badgePath, with: .color(color))
    context.stroke(badgePath, with: .color(state.textColor.opacity(0.4)), lineWidth: 1)
    context.draw(badgeText(label: label, alpha: alpha), at: rect.center)
  }

  private func badgeText(label: String, alpha: Double) -> Text {
    let font = Font.system(size: state.badgeFontSize, weight: .bold, design: .monospaced)
    let typed = state.typedPrefix
    guard !typed.isEmpty, label.hasPrefix(typed), typed.count < label.count else {
      return Text(label)
        .font(font)
        .foregroundColor(state.textColor.opacity(alpha))
    }
    return Text(String(label.prefix(typed.count)))
      .font(font)
      .foregroundColor(state.textColor.opacity(alpha))
      + Text(String(label.dropFirst(typed.count)))
      .font(font)
      .foregroundColor(state.textColor.opacity(alpha * 0.45))
  }

  private func drawGrid(_ region: CGRect, in context: inout GraphicsContext) {
    let rect = CGRect(
      x: region.minX - screen.frame.minX,
      y: screen.frame.maxY - region.maxY,
      width: region.width,
      height: region.height
    )
    let border = Path(roundedRect: rect, cornerRadius: 4)
    // Wide dark stroke under a narrow light one stays visible on any background.
    context.stroke(border, with: .color(.black.opacity(0.7)), lineWidth: 5)
    context.stroke(border, with: .color(.white.opacity(0.9)), lineWidth: 2)
    for index in 0..<9 {
      let cell = NavigationSession.gridCell(index, in: region)
      let cellRect = CGRect(
        x: cell.minX - screen.frame.minX,
        y: screen.frame.maxY - cell.maxY,
        width: cell.width,
        height: cell.height
      ).insetBy(dx: 1, dy: 1)
      let edges = Path(cellRect)
      context.stroke(edges, with: .color(.black.opacity(0.55)), lineWidth: 2.5)
      context.stroke(edges, with: .color(.white.opacity(0.6)), lineWidth: 1)
      drawGridLetter(index, at: cellRect.center, in: &context)
    }
  }

  /// Dark offsets behind the glyph act as an outline — Canvas text can't stroke.
  private func drawGridLetter(_ index: Int, at center: CGPoint, in context: inout GraphicsContext) {
    guard index < state.gridLetters.count else { return }
    let letter = Text(String(state.gridLetters[index]))
      .font(.system(size: 18, weight: .bold, design: .monospaced))
    for offset in [CGPoint(x: -1.5, y: 0), CGPoint(x: 1.5, y: 0),
                   CGPoint(x: 0, y: -1.5), CGPoint(x: 0, y: 1.5)] {
      context.draw(letter.foregroundColor(.black.opacity(0.85)),
                   at: CGPoint(x: center.x + offset.x, y: center.y + offset.y))
    }
    context.draw(letter.foregroundColor(.white), at: center)
  }

  private func drawScrollTarget(_ frame: CGRect, in context: inout GraphicsContext) {
    let canvasRect = CGRect(
      x: frame.minX - screen.frame.minX,
      y: screen.frame.maxY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
    let path = Path(roundedRect: canvasRect.insetBy(dx: 2, dy: 2), cornerRadius: 6)
    // Dual-tone stroke stays visible on light and dark content alike.
    context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 5)
    context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 2)
    let inner = Path(roundedRect: canvasRect.insetBy(dx: 5, dy: 5), cornerRadius: 4)
    context.stroke(inner, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
  }
}
