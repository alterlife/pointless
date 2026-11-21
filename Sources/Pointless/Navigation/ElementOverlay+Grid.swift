import AppKit
import SwiftUI

// MARK: - Zone Grid Drawing

extension OverlayContentView {
  func drawGrid(_ region: CGRect, hintFrame: CGRect?, in context: inout GraphicsContext) {
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

    if isFinalLevel {
      drawFinalLevelGrid(region, hintFrame: hintFrame, in: &context)
      return
    }

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
      } else {
        let label = String(qChar)
        drawGridTag(label: label, center: cellRect.center, maxHeight: cellRect.height, in: &context)
      }
    }
  }

  private func drawFinalLevelGrid(
    _ region: CGRect,
    hintFrame: CGRect?,
    in context: inout GraphicsContext
  ) {
    let count = min(9, state.gridLetters.count)

    // Spatial cell dividers
    for qIdx in 0..<count {
      let cell = NavigationSession.gridCell(qIdx, in: region)
      let cellRect = CGRect(
        x: cell.minX - screen.frame.minX,
        y: screen.frame.maxY - cell.maxY,
        width: cell.width,
        height: cell.height
      ).insetBy(dx: 1, dy: 1)
      let cellPath = Path(cellRect)
      context.stroke(cellPath, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
      context.stroke(cellPath, with: .color(state.badgeColor.opacity(0.5)), lineWidth: 0.75)
    }

    let gridRect = CGRect(
      x: region.minX - screen.frame.minX,
      y: screen.frame.maxY - region.maxY,
      width: region.width,
      height: region.height
    )

    // Labelled points placed outside the grid region
    let anchors: [CGPoint] = (0..<count).map { qIdx in
      let cell = NavigationSession.gridCell(qIdx, in: region)
      return CGPoint(
        x: cell.midX - screen.frame.minX,
        y: screen.frame.maxY - cell.midY
      )
    }
    let labels: [String] = (0..<count).map { String(state.gridLetters[$0]) }
    let badgeSizes = labels.map { measureBadge(label: $0, context: context) }
    let badgeRects = placeGridBadges(
      gridRect: gridRect,
      anchors: anchors,
      badgeSizes: badgeSizes,
      viewSize: screen.frame.size,
      topInset: 0,
      reservedRects: hintFrame.map { [$0] } ?? []
    )

    for index in 0..<count {
      let anchor = anchors[index]
      let badgeRect = badgeRects[index]
      let label = labels[index]
      drawConnector(anchor: anchor, center: badgeRect.center, alpha: 1.0, context: &context)
      drawDot(at: anchor, color: state.badgeColor, context: &context)
      drawBadge(rect: badgeRect, color: state.badgeColor, label: label, alpha: 1.0, context: &context)
    }
  }

  private func drawGridTag(
    label: String,
    center: CGPoint,
    maxHeight: CGFloat? = nil,
    in context: inout GraphicsContext
  ) {
    let size = measureBadge(label: label, context: context)
    let rect = CGRect(center: center, size: size)
    let path = Path(roundedRect: rect, cornerRadius: 4)
    context.fill(path, with: .color(state.badgeColor))
    context.stroke(path, with: .color(state.textColor.opacity(0.35)), lineWidth: 1)
    let font = Font.system(size: state.badgeFontSize, weight: .bold, design: .monospaced)
    let text = Text(label).font(font).foregroundColor(state.textColor)
    context.draw(text, at: rect.center)
  }
}
