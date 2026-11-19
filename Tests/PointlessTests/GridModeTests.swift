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

  func testGridLettersAreNineUniquePriorityKeys() {
    XCTAssertEqual(LabelGenerator.gridLetters.count, 9)
    XCTAssertEqual(Set(LabelGenerator.gridLetters).count, 9)
    XCTAssertTrue(LabelGenerator.gridLetters.allSatisfy {
      LabelGenerator.priorityKeys.contains($0)
    })
  }
}
