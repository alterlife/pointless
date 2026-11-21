import AppKit

extension NavigationSession {
  func handleZoneKey(_ event: NSEvent) {
    if eventMatchesHotkey(event, shortcut: config.gridSwitchShortcut) {
      clearGrid()
      return
    }
    switch event.keyCode {
    case 53:  // ESC
      end()
    case 51:  // Backspace
      gridBackspace()
    default:
      _ = handleGridKey(event)
    }
  }

  func handleGridKey(_ event: NSEvent) -> Bool {
    guard let region = gridRegions.last else { return false }

    if event.keyCode == 49 {  // Space → left-click current cell
      resolveGridClick(region, rightClick: false)
      return true
    }
    if event.keyCode == 36 {  // Return → right-click current cell
      resolveGridClick(region, rightClick: true)
      return true
    }

    guard let char = event.charactersIgnoringModifiers?.lowercased().first,
          let index = config.gridLetters.firstIndex(of: char) else { return false }
    let cell = Self.gridCell(index, in: region)
    gridPath.append(char)
    overlayState.gridBreadcrumb = Self.formatBreadcrumb(path: gridPath, maxLevel: config.gridMaxLevel)
    overlayState.gridPathPrefix = String(gridPath)
    if gridRegions.count >= config.gridMaxLevel {
      if config.gridAutoClick {
        resolveGridClick(cell, rightClick: false)
      } else {
        warpCursor(to: cell)
        gridRegions.append(cell)
        overlayState.gridRegion = cell
      }
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
    gridPath = []
    overlayState.gridRegion = screen.frame
    overlayState.gridBreadcrumb = Self.formatBreadcrumb(path: gridPath, maxLevel: config.gridMaxLevel)
    overlayState.gridPathPrefix = ""
    updatePrefix("")
    showBadges()
  }

  func gridBackspace() {
    guard gridRegions.count > 1 else {
      clearGrid()
      return
    }
    gridRegions.removeLast()
    if !gridPath.isEmpty { gridPath.removeLast() }
    overlayState.gridRegion = gridRegions.last
    overlayState.gridBreadcrumb = Self.formatBreadcrumb(path: gridPath, maxLevel: config.gridMaxLevel)
    overlayState.gridPathPrefix = String(gridPath)
  }

  func clearGrid() {
    gridRegions.removeAll()
    gridPath.removeAll()
    overlayState.gridRegion = nil
    overlayState.gridBreadcrumb = ""
    overlayState.gridPathPrefix = ""
    showBadges()
  }

  private func resolveGridClick(_ cell: CGRect, rightClick: Bool) {
    let address = String(gridPath)
    let center = CGPoint(x: cell.midX, y: cell.midY)
    let clickPoint = cgPoint(fromAppKit: center)
    CGWarpMouseCursorPosition(clickPoint)
    CGAssociateMouseAndMouseCursorPosition(1)
    clearGrid()
    onJump()
    end()
    showSpatialAddressToast(address.isEmpty ? "center" : address, at: center)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      if rightClick {
        Self.postRightClick(at: clickPoint)
      } else {
        Self.postClick(at: clickPoint)
      }
    }
  }

  private func warpCursor(to cell: CGRect) {
    CGWarpMouseCursorPosition(cgPoint(fromAppKit: CGPoint(x: cell.midX, y: cell.midY)))
    CGAssociateMouseAndMouseCursorPosition(1)
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

  nonisolated static func formatBreadcrumb(path: [Character], maxLevel: Int) -> String {
    var slots: [String] = []
    for index in 0..<maxLevel {
      if index < path.count {
        slots.append(String(path[index]))
      } else {
        slots.append("·")
      }
    }
    return "[ " + slots.joined(separator: " ") + " ]"
  }
}
