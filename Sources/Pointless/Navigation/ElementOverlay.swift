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

/// Collapsed members stay faint until their group prefix is typed; once
/// typing narrows, non-matching badges dim as usual.
func badgeAlpha(label: String, isCollapsedMember: Bool, typedPrefix: String) -> Double {
  if isCollapsedMember && typedPrefix.isEmpty { return 0.15 }
  if !typedPrefix.isEmpty && !label.hasPrefix(typedPrefix) { return 0.2 }
  return 1.0
}

/// nil once the prefix is fully typed — the signpost has done its job.
func groupBadgeAlpha(prefix: String, typedPrefix: String) -> Double? {
  if typedPrefix.isEmpty { return 1.0 }
  if typedPrefix.count >= prefix.count, prefix.hasPrefix(typedPrefix) { return nil }
  return prefix.hasPrefix(typedPrefix) ? 1.0 : 0.2
}

final class OverlayState: ObservableObject {
  @Published var labeledElements: [LabeledElement] = []
  @Published var collapsedGroups: [CollapsedGroup] = []
  @Published var typedPrefix: String = ""
  @Published var scrollTargetFrame: CGRect?
  @Published var scrollOutlineHidden = false
  @Published var showScrollHint = false
  @Published var clickHintDismissed = false
  @Published var revealElementText = false

  var collapsedPrefixes: Set<String> { Set(collapsedGroups.map(\.prefix)) }

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
        let groupsOnScreen = state.collapsedGroups.filter {
          badgeScreen(for: $0.frame, among: allScreenFrames) == screen.frame
        }
        let anchors = onScreen.map {
          anchorPoint(screenFrame: $0.element.screenFrame, screenRect: screen.frame)
        } + groupsOnScreen.map {
          anchorPoint(screenFrame: $0.frame, screenRect: screen.frame)
        }
        let badgeSizes = onScreen.map {
          measureBadge(label: displayText(for: $0), context: ctx)
        } + groupsOnScreen.map {
          measureBadge(label: $0.label, context: ctx)
        }
        let badgeRects = placeBadges(
          anchors: anchors, badgeSizes: badgeSizes, viewSize: size,
          topInset: screen.safeAreaInsets.top,
          reservedRects: hint.map { [$0.insetBy(dx: -4, dy: -4)] } ?? []
        )
        for group in groupsOnScreen {
          drawGroupFrame(group, in: &ctx)
        }
        for (index, labeled) in onScreen.enumerated() {
          drawElement(labeled, badgeRect: badgeRects[index], anchor: anchors[index], in: &ctx)
        }
        for (index, group) in groupsOnScreen.enumerated() {
          let badgeIndex = onScreen.count + index
          drawGroupBadge(
            group, badgeRect: badgeRects[badgeIndex], anchor: anchors[badgeIndex], in: &ctx
          )
        }
        if let target = state.scrollTargetFrame, !state.scrollOutlineHidden {
          drawScrollTarget(target, in: &ctx)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if let hint {
        escHint
      }
    }
  }

  private var hintText: String {
    state.scrollTargetFrame != nil
      ? "j/k scroll  ·  d/u half page  ·  ⌘⇧J next  ·  ⌘⇧K prev  ·  ESC exit"
      : "type a letter to jump  ·  ⌫ back  ·  hold ⌘ for text  ·  ESC cancel"
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
    let isCollapsedMember = state.collapsedPrefixes.contains { labeled.label.hasPrefix($0) }
    let alpha = badgeAlpha(
      label: labeled.label, isCollapsedMember: isCollapsedMember, typedPrefix: state.typedPrefix
    )
    let fillColor = state.badgeColor.opacity(alpha)

    drawConnector(anchor: anchor, center: badgeRect.center, alpha: alpha, context: &context)
    drawDot(at: anchor, color: fillColor, context: &context)
    drawBadge(
      rect: badgeRect, color: fillColor, label: displayText(for: labeled),
      alpha: alpha, context: &context
    )
  }

  private func displayText(for labeled: LabeledElement) -> String {
    guard state.revealElementText else { return labeled.label }
    let text = labeled.element.text
    guard !text.isEmpty else { return labeled.label }
    let preview = text.count > 48 ? String(text.prefix(48)) + "…" : text
    return "\(labeled.label) (\(preview))"
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
    if state.revealElementText {
      return Text(label)
        .font(.system(size: state.badgeFontSize, weight: .bold, design: .monospaced))
        .foregroundColor(state.textColor.opacity(alpha))
    }
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

  private func drawGroupFrame(_ group: CollapsedGroup, in context: inout GraphicsContext) {
    guard let alpha = groupBadgeAlpha(prefix: group.prefix, typedPrefix: state.typedPrefix)
    else { return }
    let frame = group.frame
    let canvasRect = CGRect(
      x: frame.minX - screen.frame.minX,
      y: screen.frame.maxY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
    let path = Path(roundedRect: canvasRect.insetBy(dx: -3, dy: -3), cornerRadius: 8)
    context.fill(path, with: .color(state.badgeColor.opacity(alpha * 0.06)))
    context.stroke(path, with: .color(state.badgeColor.opacity(alpha * 0.5)), lineWidth: 1.5)
  }

  private func drawGroupBadge(
    _ group: CollapsedGroup,
    badgeRect: CGRect,
    anchor: CGPoint,
    in context: inout GraphicsContext
  ) {
    guard let alpha = groupBadgeAlpha(prefix: group.prefix, typedPrefix: state.typedPrefix)
    else { return }
    let fillColor = state.badgeColor.opacity(alpha)
    drawConnector(anchor: anchor, center: badgeRect.center, alpha: alpha, context: &context)
    drawDot(at: anchor, color: fillColor, context: &context)
    drawBadge(rect: badgeRect, color: fillColor, label: group.label, alpha: alpha, context: &context)
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
