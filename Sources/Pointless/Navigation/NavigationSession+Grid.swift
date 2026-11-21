import AppKit

extension NavigationSession {
  static let gridMaxLevel = 4

  func handleGridKey(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(config.gridModifier) else { return false }
    startGrid()
    guard let char = event.charactersIgnoringModifiers?.lowercased().first,
          let index = LabelGenerator.gridLetters.firstIndex(of: char),
          let region = gridRegions.last else { return false }
    let cell = Self.gridCell(index, in: region)
    if gridRegions.count >= Self.gridMaxLevel {
      resolveGrid(cell)
    } else {
      gridRegions.append(cell)
      overlayState.gridRegion = cell
    }
    return true
  }

  func startGrid() {
    guard gridRegions.isEmpty else { return }
    let screen = NSScreen.screens.first {
      NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
    } ?? NSScreen.main
    guard let screen else { return }
    gridRegions = [screen.frame]
    overlayState.gridRegion = screen.frame
  }

  func gridBackspace() {
    guard gridRegions.count > 1 else {
      clearGrid()
      return
    }
    gridRegions.removeLast()
    overlayState.gridRegion = gridRegions.last
  }

  func clearGrid() {
    gridRegions.removeAll()
    overlayState.gridRegion = nil
  }

  private func resolveGrid(_ cell: CGRect) {
    CGWarpMouseCursorPosition(cgPoint(fromAppKit: CGPoint(x: cell.midX, y: cell.midY)))
    CGAssociateMouseAndMouseCursorPosition(1)
    clearGrid()
  }

  /// Row 0 is the top of the region — AppKit y grows upward.
  nonisolated static func gridCell(_ index: Int, in region: CGRect) -> CGRect {
    let cellWidth = region.width / 3
    let cellHeight = region.height / 3
    let column = index % 3
    let row = index / 3
    return CGRect(
      x: region.minX + CGFloat(column) * cellWidth,
      y: region.maxY - CGFloat(row + 1) * cellHeight,
      width: cellWidth,
      height: cellHeight
    )
  }
}
