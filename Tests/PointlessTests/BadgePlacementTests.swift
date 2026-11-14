import XCTest
@testable import PointlessCore
import CoreGraphics

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
    // Visual top-left (maxY 950) sits on the upper screen; body extends down onto
    // the lower one, which is listed first so a plain overlap check would pick it.
    let element = CGRect(x: 100, y: 850, width: 50, height: 100)

    XCTAssertEqual(badgeScreen(for: element, among: [lowerScreen, upperScreen]), upperScreen)
  }

  func testAnchorOffAllScreensFallsBackToOverlappingScreen() {
    let element = CGRect(x: -100, y: 200, width: 300, height: 40)

    XCTAssertEqual(badgeScreen(for: element, among: [upperScreen, lowerScreen]), lowerScreen)
  }
}
