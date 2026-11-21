import AppKit
import SwiftUI

// MARK: - Zone Grid Drawing

extension OverlayContentView {
  func drawGrid(_ region: CGRect, in context: inout GraphicsContext) {
    guard screen.frame.intersects(region) else { return }
    let rect = CGRect(
      x: region.minX - screen.frame.minX,
      y: screen.frame.maxY - region.maxY,
      width: region.width,
      height: region.height
    )
    let border = Path(roundedRect: rect, cornerRadius: 6)
    context.stroke(border, with: .color(.black.opacity(0.4)), lineWidth: 3)
    context.stroke(border, with: .color(state.badgeColor), lineWidth: 1.5)

    let isUpperLevel = state.gridPathPrefix.isEmpty
    let canSubdivide = isUpperLevel && (state.gridMaxLevel >= 2)
    let isFinalLevel = (state.gridPathPrefix.count + 1 >= state.gridMaxLevel)

    for qIdx in 0..<min(9, state.gridLetters.count) {
      let cell = NavigationSession.gridCell(qIdx, in: region)
      let cellRect = CGRect(
        x: cell.minX - screen.frame.minX,
        y: screen.frame.maxY - cell.maxY,
        width: cell.width,
        height: cell.height
      ).insetBy(dx: 1, dy: 1)
      let qChar = state.gridLetters[qIdx]

      let cellPath = Path(cellRect)
      context.stroke(cellPath, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
      context.stroke(cellPath, with: .color(state.badgeColor.opacity(0.5)), lineWidth: 0.75)

      if canSubdivide && cell.width >= 120 && cell.height >= 70 {
        for sIdx in 0..<min(9, state.gridLetters.count) {
          let subCell = NavigationSession.gridCell(sIdx, in: cell)
          let subRect = CGRect(
            x: subCell.minX - screen.frame.minX,
            y: screen.frame.maxY - subCell.maxY,
            width: subCell.width,
            height: subCell.height
          )
          context.stroke(Path(subRect), with: .color(.black.opacity(0.18)), lineWidth: 0.75)
          let sChar = state.gridLetters[sIdx]
          let label = "\(qChar)\(sChar)"
          drawGridTag(label: label, center: subRect.center, in: &context)
        }
      } else if isFinalLevel {
        drawFinalLevelCell(qIdx: qIdx, qChar: qChar, cellRect: cellRect, in: &context)
      } else {
        let label = String(qChar)
        drawGridTag(label: label, center: cellRect.center, maxHeight: cellRect.height, in: &context)
      }
    }
  }

  private func drawFinalLevelCell(
    qIdx: Int,
    qChar: Character,
    cellRect: CGRect,
    in context: inout GraphicsContext
  ) {
    let label = String(qChar)
    let anchor = cellRect.center
    let badgeSize = measureGridTag(label: label, maxHeight: cellRect.height, context: context)
    let badgeCenter = finalLevelBadgeCenter(for: qIdx, in: cellRect, badgeSize: badgeSize)

    if state.showConnectorLines {
      var connector = Path()
      connector.move(to: anchor)
      connector.addLine(to: badgeCenter)
      context.stroke(connector, with: .color(state.badgeColor.opacity(0.7)), lineWidth: 1.2)
    }

    let dotRect = CGRect(center: anchor, size: CGSize(width: 5, height: 5))
    context.fill(Path(ellipseIn: dotRect), with: .color(state.badgeColor))
    context.stroke(Path(ellipseIn: dotRect), with: .color(.black.opacity(0.6)), lineWidth: 0.75)

    drawGridTag(label: label, center: badgeCenter, maxHeight: cellRect.height, in: &context)
  }

  private func finalLevelBadgeCenter(for qIdx: Int, in cellRect: CGRect, badgeSize: CGSize) -> CGPoint {
    let col = qIdx % 3
    let row = qIdx / 3

    let badgeX: CGFloat
    switch col {
    case 0:
      badgeX = cellRect.minX + badgeSize.width / 2 + 2
    case 2:
      badgeX = cellRect.maxX - badgeSize.width / 2 - 2
    default:
      badgeX = (row == 1) ? (cellRect.minX + badgeSize.width / 2 + 2) : cellRect.midX
    }

    let badgeY: CGFloat
    switch row {
    case 0:
      badgeY = cellRect.minY + badgeSize.height / 2 + 2
    case 2:
      badgeY = cellRect.maxY - badgeSize.height / 2 - 2
    default:
      badgeY = cellRect.minY + badgeSize.height / 2 + 2
    }

    return CGPoint(x: badgeX, y: badgeY)
  }

  private func measureGridTag(label: String, maxHeight: CGFloat?, context: GraphicsContext) -> CGSize {
    let baseFontSize = state.badgeFontSize
    let fontSize = maxHeight.map { min(baseFontSize, max(8, $0 * 0.5)) } ?? baseFontSize
    let font = Font.system(size: fontSize, weight: .bold, design: .monospaced)
    let text = Text(label).font(font)
    let resolved = context.resolve(text)
    let measured = resolved.measure(in: CGSize(width: 100, height: 50))
    return CGSize(width: measured.width + 8, height: measured.height + 4)
  }

  private func drawGridTag(
    label: String,
    center: CGPoint,
    maxHeight: CGFloat? = nil,
    in context: inout GraphicsContext
  ) {
    let size = measureGridTag(label: label, maxHeight: maxHeight, context: context)
    let rect = CGRect(center: center, size: size)
    let path = Path(roundedRect: rect, cornerRadius: 4)
    context.fill(path, with: .color(state.badgeColor))
    context.stroke(path, with: .color(state.textColor.opacity(0.35)), lineWidth: 1)
    let baseFontSize = state.badgeFontSize
    let fontSize = maxHeight.map { min(baseFontSize, max(8, $0 * 0.5)) } ?? baseFontSize
    let font = Font.system(size: fontSize, weight: .bold, design: .monospaced)
    let text = Text(label).font(font).foregroundColor(state.textColor)
    context.draw(text, at: rect.center)
  }
}
