import CoreGraphics
@testable import PointlessCore
import XCTest

final class BadgePlacementTests: XCTestCase {
  private let viewSize = CGSize(width: 500, height: 500)
  private let badgeSize = CGSize(width: 20, height: 16)

  private func anchorRect(_ center: CGPoint) -> CGRect {
    CGRect(center: center, size: CGSize(width: 8, height: 8))
  }

  private func place(
    anchor: CGPoint,
    anchorRects: [CGRect],
    ownAnchorIndex: Int = 0,
    placedBadges: [CGRect] = []
  ) -> CGRect {
    placeBadge(
      anchor: anchor, badgeSize: badgeSize, viewSize: viewSize,
      obstacles: BadgeObstacles(anchorRects: anchorRects, placedBadges: placedBadges),
      ownAnchorIndex: ownAnchorIndex
    )
  }

  func testPrefersAboveLeftWhenClear() {
    let anchor = CGPoint(x: 250, y: 250)
    let rect = place(anchor: anchor, anchorRects: [anchorRect(anchor)])

    XCTAssertEqual(rect.origin.x, anchor.x - badgeSize.width - 4, accuracy: 0.001)
    XCTAssertEqual(rect.origin.y, anchor.y - badgeSize.height - 6, accuracy: 0.001)
  }

  func testShiftsToAlternateCandidateWhenAnchorBlocked() {
    let anchor = CGPoint(x: 250, y: 250)
    // Above-left candidate occupies x 226-246, y 228-244 — block it with
    // another element's anchor at (236, 236).
    let rect = place(
      anchor: anchor,
      anchorRects: [anchorRect(anchor), anchorRect(CGPoint(x: 236, y: 236))],
      ownAnchorIndex: 0
    )

    // Next candidate: above-right at (anchor.x + 4, anchor.y - h - 6)
    XCTAssertEqual(rect.origin.x, anchor.x + 4, accuracy: 0.001)
    XCTAssertEqual(rect.origin.y, anchor.y - badgeSize.height - 6, accuracy: 0.001)
  }

  func testAvoidsAlreadyPlacedBadge() {
    let anchor = CGPoint(x: 250, y: 250)
    let placed = CGRect(
      x: anchor.x - badgeSize.width - 4,
      y: anchor.y - badgeSize.height - 6,
      width: badgeSize.width,
      height: badgeSize.height
    )
    let rect = place(anchor: anchor, anchorRects: [anchorRect(anchor)], placedBadges: [placed])

    XCTAssertFalse(rect.intersects(placed.insetBy(dx: -2, dy: -2)))
  }

  func testClampsInsideViewBounds() {
    for anchor in [CGPoint(x: 6, y: 6), CGPoint(x: 494, y: 494)] {
      let rect = place(anchor: anchor, anchorRects: [anchorRect(anchor)])
      XCTAssertGreaterThanOrEqual(rect.minX, 4)
      XCTAssertGreaterThanOrEqual(rect.minY, 4)
      XCTAssertLessThanOrEqual(rect.maxX, viewSize.width - 4 + 0.001)
      XCTAssertLessThanOrEqual(rect.maxY, viewSize.height - 4 + 0.001)
    }
  }

  func testOwnAnchorDoesNotBlockBadge() {
    let anchor = CGPoint(x: 250, y: 250)
    let rect = place(anchor: anchor, anchorRects: [anchorRect(anchor)])
    XCTAssertEqual(rect.origin.x, anchor.x - badgeSize.width - 4, accuracy: 0.001)
  }

  func testFallbackReturnsRectWhenAllCandidatesBlocked() {
    let anchor = CGPoint(x: 250, y: 250)
    // Block all four candidate zones with other elements' anchors.
    let obstacles = [
      anchorRect(anchor),
      anchorRect(CGPoint(x: 236, y: 236)),  // above-left
      anchorRect(CGPoint(x: 264, y: 236)),  // above-right
      anchorRect(CGPoint(x: 236, y: 272)),  // below-left
      anchorRect(CGPoint(x: 264, y: 272))   // below-right
    ]
    let rect = place(anchor: anchor, anchorRects: obstacles, ownAnchorIndex: 0)

    XCTAssertEqual(rect.width, badgeSize.width, accuracy: 0.001)
    XCTAssertEqual(rect.height, badgeSize.height, accuracy: 0.001)
  }

  func testTopInsetKeepsBadgeBelowNotchStrip() {
    // Notched screens report safeAreaInsets.top = 32 — badges must not enter it.
    let anchor = CGPoint(x: 250, y: 20)
    let rect = placeBadge(
      anchor: anchor, badgeSize: badgeSize, viewSize: viewSize,
      obstacles: BadgeObstacles(anchorRects: [anchorRect(anchor)]),
      ownAnchorIndex: 0, topInset: 32
    )

    XCTAssertGreaterThanOrEqual(rect.minY, 36)
  }

  func testPlaceBadgesAssignsSequentialObstacles() {
    // Two anchors close together: the second badge must not cover the first's anchor.
    let anchors = [CGPoint(x: 250, y: 250), CGPoint(x: 236, y: 236)]
    let sizes = [badgeSize, badgeSize]
    let rects = placeBadges(anchors: anchors, badgeSizes: sizes, viewSize: viewSize)

    XCTAssertEqual(rects.count, 2)
    let secondAnchorObstacle = CGRect(center: anchors[1], size: CGSize(width: 8, height: 8))
    XCTAssertFalse(rects[0].intersects(secondAnchorObstacle))
  }

  // MARK: badgeScreen

  private let lowerScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  private let upperScreen = CGRect(x: 0, y: 900, width: 1440, height: 900)

  func testBadgeDrawnOnlyOnScreenHoldingElement() {
    let element = CGRect(x: 100, y: 1200, width: 50, height: 20)

    XCTAssertEqual(badgeScreen(for: element, among: [lowerScreen, upperScreen]), upperScreen)
  }

  func testSpanningElementUsesScreenHoldingAnchor() {
    // Anchor (midY 910) sits on the upper screen; body extends down onto the
    // lower one, which is listed first so a plain overlap check would pick it.
    let element = CGRect(x: 100, y: 860, width: 50, height: 100)

    XCTAssertEqual(badgeScreen(for: element, among: [lowerScreen, upperScreen]), upperScreen)
  }

  func testAnchorOffAllScreensFallsBackToOverlappingScreen() {
    let element = CGRect(x: -100, y: 200, width: 300, height: 40)

    XCTAssertEqual(badgeScreen(for: element, among: [upperScreen, lowerScreen]), lowerScreen)
  }

  // MARK: Badge alpha

  func testNonMatchingBadgeDimsWhileTyping() {
    XCTAssertEqual(badgeAlpha(label: "sa", typedPrefix: ""), 1.0)
    XCTAssertEqual(badgeAlpha(label: "sa", typedPrefix: "s"), 1.0)
    XCTAssertEqual(badgeAlpha(label: "sa", typedPrefix: "a"), 0.2)
  }

  // MARK: placeGridBadges

  func testPlaceGridBadgesPlacesOutsideGridRegion() {
    let gridRect = CGRect(x: 500, y: 400, width: 64, height: 40)
    let cellW = gridRect.width / 3
    let cellH = gridRect.height / 3
    let anchors: [CGPoint] = (0..<9).map { idx in
      let col = CGFloat(idx % 3)
      let row = CGFloat(idx / 3)
      return CGPoint(x: gridRect.minX + (col + 0.5) * cellW, y: gridRect.minY + (row + 0.5) * cellH)
    }
    let sizes = [CGSize](repeating: CGSize(width: 18, height: 18), count: 9)
    let badges = placeGridBadges(
      gridRect: gridRect,
      anchors: anchors,
      badgeSizes: sizes,
      viewSize: CGSize(width: 1728, height: 1117)
    )

    XCTAssertEqual(badges.count, 9)
    for (idx, badge) in badges.enumerated() {
      XCTAssertFalse(gridRect.intersects(badge), "Badge \(idx) should not intersect gridRect")
    }
  }

  func testPlaceGridBadgesAvoidsCollisionsBetweenBadges() {
    let gridRect = CGRect(x: 300, y: 300, width: 90, height: 60)
    let cellW = gridRect.width / 3
    let cellH = gridRect.height / 3
    let anchors: [CGPoint] = (0..<9).map { idx in
      let col = CGFloat(idx % 3)
      let row = CGFloat(idx / 3)
      return CGPoint(x: gridRect.minX + (col + 0.5) * cellW, y: gridRect.minY + (row + 0.5) * cellH)
    }
    let sizes = [CGSize](repeating: CGSize(width: 20, height: 18), count: 9)
    let badges = placeGridBadges(
      gridRect: gridRect,
      anchors: anchors,
      badgeSizes: sizes,
      viewSize: CGSize(width: 1728, height: 1117)
    )

    for firstIndex in 0..<badges.count {
      for secondIndex in (firstIndex + 1)..<badges.count {
        XCTAssertFalse(
          badges[firstIndex].intersects(badges[secondIndex]),
          "Badge \(firstIndex) and \(secondIndex) should not collide"
        )
      }
    }
  }

  func testPlaceGridBadgesNearScreenEdge() {
    let gridRect = CGRect(x: 4, y: 4, width: 64, height: 40)
    let cellW = gridRect.width / 3
    let cellH = gridRect.height / 3
    let anchors: [CGPoint] = (0..<9).map { idx in
      let col = CGFloat(idx % 3)
      let row = CGFloat(idx / 3)
      return CGPoint(x: gridRect.minX + (col + 0.5) * cellW, y: gridRect.minY + (row + 0.5) * cellH)
    }
    let sizes = [CGSize](repeating: CGSize(width: 18, height: 18), count: 9)
    let badges = placeGridBadges(
      gridRect: gridRect,
      anchors: anchors,
      badgeSizes: sizes,
      viewSize: CGSize(width: 1728, height: 1117)
    )

    for (idx, badge) in badges.enumerated() {
      XCTAssertGreaterThanOrEqual(badge.minX, 4, "Badge \(idx) should stay on screen (minX)")
      XCTAssertGreaterThanOrEqual(badge.minY, 4, "Badge \(idx) should stay on screen (minY)")
    }
  }

  func testPlaceGridBadgesCenterCellDoesNotMeldWithCardinalLines() {
    let gridRect = CGRect(x: 500, y: 400, width: 64, height: 40)
    let cellW = gridRect.width / 3
    let cellH = gridRect.height / 3
    let anchors: [CGPoint] = (0..<9).map { idx in
      let col = CGFloat(idx % 3)
      let row = CGFloat(idx / 3)
      return CGPoint(x: gridRect.minX + (col + 0.5) * cellW, y: gridRect.minY + (row + 0.5) * cellH)
    }
    let sizes = [CGSize](repeating: CGSize(width: 18, height: 18), count: 9)
    let badges = placeGridBadges(
      gridRect: gridRect,
      anchors: anchors,
      badgeSizes: sizes,
      viewSize: CGSize(width: 1728, height: 1117)
    )

    let centerBadge = badges[4]
    // Center badge must not share exact midX with cell 1 or 7 (cardinal vertical lines)
    XCTAssertGreaterThan(abs(centerBadge.center.x - anchors[1].x), 2.0)
    XCTAssertGreaterThan(abs(centerBadge.center.x - anchors[7].x), 2.0)

    // Center badge must not share exact midY with cell 3 or 5 (cardinal horizontal lines)
    XCTAssertGreaterThan(abs(centerBadge.center.y - anchors[3].y), 2.0)
    XCTAssertGreaterThan(abs(centerBadge.center.y - anchors[5].y), 2.0)
  }
}
