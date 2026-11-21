import XCTest
@testable import PointlessCore
import CoreGraphics

final class GridModeTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

  func testCellsPartitionRegion() {
    var covered = CGRect.null
    for index in 0..<9 {
      covered = covered.union(NavigationSession.gridCell(index, in: screen))
    }
    XCTAssertEqual(covered, screen)
  }

  func testCellsAreDisjoint() {
    for i in 0..<9 {
      for j in (i + 1)..<9 {
        let a = NavigationSession.gridCell(i, in: screen)
        let b = NavigationSession.gridCell(j, in: screen)
        let overlap = a.intersection(b)
        XCTAssertTrue(overlap.width <= 0 || overlap.height <= 0, "cells \(i) and \(j) overlap")
      }
    }
  }

  func testTopLeftCellIsFirst() {
    // AppKit y grows upward: index 0 must be the top-left cell.
    let cell = NavigationSession.gridCell(0, in: screen)
    XCTAssertEqual(cell.minX, 0)
    XCTAssertEqual(cell.maxY, screen.maxY)
    XCTAssertEqual(cell.width, 640)
    XCTAssertEqual(cell.height, 360)
  }

  func testBottomRightCellIsLast() {
    let cell = NavigationSession.gridCell(8, in: screen)
    XCTAssertEqual(cell.maxX, screen.maxX)
    XCTAssertEqual(cell.minY, screen.minY)
  }

  func testGridLettersClustersHaveNineUniqueKeys() {
    let clusters = [
      LabelGenerator.rightHandGridLetters,
      LabelGenerator.leftHandGridLetters,
      LabelGenerator.classicGridLetters
    ]
    for cluster in clusters {
      XCTAssertEqual(cluster.count, 9)
      XCTAssertEqual(Set(cluster).count, 9)
    }
    XCTAssertTrue(LabelGenerator.classicGridLetters.allSatisfy {
      LabelGenerator.priorityKeys.contains($0)
    })
    XCTAssertEqual(LabelGenerator.gridLetters, LabelGenerator.rightHandGridLetters)
  }

  @MainActor
  func testGridSwitchHotkeyConfiguration() {
    let nav = KeyboardNavigation()
    nav.configure(with: ["gridSwitchHotkey": "⌥Space"])
    XCTAssertEqual(nav.gridSwitchShortcutDisplay, "⌥Space")
    XCTAssertEqual(nav.gridSwitchShortcut.keyCode, 49)
    XCTAssertTrue(nav.gridSwitchShortcut.modifiers.contains(.option))
    XCTAssertEqual(nav.overlayState.gridSwitchShortcutHint, "⌥Space")

    nav.configure(with: [:])
    XCTAssertEqual(nav.gridSwitchShortcutDisplay, "Tab")
    XCTAssertEqual(nav.gridSwitchShortcut.keyCode, 48)
    XCTAssertTrue(nav.gridSwitchShortcut.modifiers.isEmpty)
    XCTAssertEqual(nav.overlayState.gridSwitchShortcutHint, "Tab")
  }

  @MainActor
  func testNavigationSessionZoneSwitchAndIsolation() {
    let state = OverlayState()
    let config = NavigationSession.Config(
      fadeInDuration: 0,
      scrollSpeed: 1,
      labelStrategy: .useHomeRowKeys,
      scrollNext: ParsedShortcut(modifiers: [], keyCode: 38),
      scrollPrev: ParsedShortcut(modifiers: [], keyCode: 40),
      gridSwitchShortcut: ParsedShortcut(modifiers: [], keyCode: 48),
      gridLetters: LabelGenerator.rightHandGridLetters,
      gridMaxLevel: 4,
      gridAutoClick: true
    )
    let session = NavigationSession(
      overlayState: state,
      config: config,
      onScanCompleted: { _ in },
      onJump: {},
      onEnded: {}
    )

    // Initially in label mode with no grid region
    XCTAssertNil(state.gridRegion)

    // Press Tab (keyCode 48) -> switches to Zone mode
    let tabEvent = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\t",
      charactersIgnoringModifiers: "\t",
      isARepeat: false,
      keyCode: 48
    )!
    session.handleKey(tabEvent)
    XCTAssertNotNil(state.gridRegion)
    XCTAssertFalse(session.gridRegions.isEmpty)

    // In Zone mode, non-grid key (e.g. 'z') is ignored and does not activate elements
    let nonGridEvent = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "z",
      charactersIgnoringModifiers: "z",
      isARepeat: false,
      keyCode: 6
    )!
    session.handleKey(nonGridEvent)
    XCTAssertEqual(session.gridRegions.count, 1)

    // Grid key 'u' (index 0, top-left) zooms down one level
    let gridKeyEvent = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "u",
      charactersIgnoringModifiers: "u",
      isARepeat: false,
      keyCode: 32
    )!
    session.handleKey(gridKeyEvent)
    XCTAssertEqual(session.gridRegions.count, 2)

    // Pressing Tab again switches back to Label mode
    session.handleKey(tabEvent)
    XCTAssertNil(state.gridRegion)
    XCTAssertTrue(session.gridRegions.isEmpty)

    session.end()
  }
}
