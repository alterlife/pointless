import CoreGraphics

// MARK: - CGRect helpers

extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
  init(center: CGPoint, size: CGSize) {
    self.init(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}

// MARK: - Coordinate utilities (internal for testability)

private let badgeAnchorInset: CGFloat = 10

private func elementAnchor(screenFrame: CGRect) -> CGPoint {
  CGPoint(x: anchorX(in: screenFrame), y: screenFrame.midY)
}

// Landscape controls center their content; everything else anchors left.
private func anchorX(in frame: CGRect) -> CGFloat {
  guard frame.width > frame.height else {
    return frame.minX + min(badgeAnchorInset, frame.width / 4)
  }
  return frame.midX
}

internal func anchorPoint(screenFrame: CGRect, screenRect: CGRect) -> CGPoint {
  let anchor = elementAnchor(screenFrame: screenFrame)
  return CGPoint(x: anchor.x - screenRect.minX, y: screenRect.maxY - anchor.y)
}

/// Frame of the screen that draws an element's badge — the one holding its
/// anchor, else the first it overlaps. Keeps each badge on exactly one overlay.
internal func badgeScreen(for elementFrame: CGRect, among screenFrames: [CGRect]) -> CGRect? {
  let anchor = elementAnchor(screenFrame: elementFrame)
  return screenFrames.first { $0.contains(anchor) }
    ?? screenFrames.first { $0.intersects(elementFrame) }
}

struct BadgeObstacles {
  var anchorRects: [CGRect] = []
  var placedBadges: [CGRect] = []
}

internal func placeBadges(
  anchors: [CGPoint], badgeSizes: [CGSize], viewSize: CGSize,
  topInset: CGFloat = 0, reservedRects: [CGRect] = []
) -> [CGRect] {
  var obstacles = BadgeObstacles(
    anchorRects: anchors.map { CGRect(center: $0, size: CGSize(width: 8, height: 8)) },
    placedBadges: reservedRects
  )
  return anchors.indices.map { index in
    let rect = placeBadge(
      anchor: anchors[index], badgeSize: badgeSizes[index], viewSize: viewSize,
      obstacles: obstacles, ownAnchorIndex: index, topInset: topInset
    )
    obstacles.placedBadges.append(rect)
    return rect
  }
}

internal func placeBadge(
  anchor: CGPoint,
  badgeSize: CGSize,
  viewSize: CGSize,
  obstacles: BadgeObstacles,
  ownAnchorIndex: Int,
  topInset: CGFloat = 0
) -> CGRect {
  let candidates = [
    CGPoint(x: anchor.x - badgeSize.width - 4, y: anchor.y - badgeSize.height - 6),
    CGPoint(x: anchor.x + 4, y: anchor.y - badgeSize.height - 6),
    CGPoint(x: anchor.x - badgeSize.width - 4, y: anchor.y + 10),
    CGPoint(x: anchor.x + 4, y: anchor.y + 10),
    CGPoint(x: anchor.x - badgeSize.width / 2, y: anchor.y - badgeSize.height - 6),
    CGPoint(x: anchor.x - badgeSize.width / 2, y: anchor.y + 10),
    CGPoint(x: anchor.x - badgeSize.width - 4, y: anchor.y - badgeSize.height / 2),
    CGPoint(x: anchor.x + 4, y: anchor.y - badgeSize.height / 2)
  ]

  func clamped(_ origin: CGPoint) -> CGPoint {
    CGPoint(
      x: max(4, min(origin.x, viewSize.width - badgeSize.width - 4)),
      y: max(topInset + 4, min(origin.y, viewSize.height - badgeSize.height - 4))
    )
  }

  func collisionCount(_ rect: CGRect) -> Int {
    let anchorHits = obstacles.anchorRects.enumerated().filter { index, anchorRect in
      index != ownAnchorIndex && anchorRect.intersects(rect)
    }.count
    let badgeHits = obstacles.placedBadges.filter {
      $0.insetBy(dx: -2, dy: -2).intersects(rect)
    }.count
    return anchorHits + badgeHits
  }

  let rects = candidates.map { CGRect(origin: clamped($0), size: badgeSize) }
  if let free = rects.first(where: { collisionCount($0) == 0 }) { return free }
  return rects.min { collisionCount($0) < collisionCount($1) } ?? rects[0]
}
