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

// MARK: - Final Zoom Grid Badge Placement (Outside-the-Grid)

internal func placeGridBadges(
  gridRect: CGRect,
  anchors: [CGPoint],
  badgeSizes: [CGSize],
  viewSize: CGSize,
  topInset: CGFloat = 0,
  reservedRects: [CGRect] = []
) -> [CGRect] {
  let margin: CGFloat = 8
  let context = GridBadgeContext(
    gridRect: gridRect,
    viewSize: viewSize,
    topInset: topInset,
    margin: margin
  )
  var obstacles = BadgeObstacles(
    anchorRects: anchors.map { CGRect(center: $0, size: CGSize(width: 8, height: 8)) },
    placedBadges: reservedRects
  )

  var results = [CGRect](repeating: .zero, count: anchors.count)
  let placementOrder = [0, 1, 2, 3, 5, 6, 7, 8, 4].filter { $0 < anchors.count }

  for idx in placementOrder {
    let bSize = badgeSizes[idx]
    let candPoints = gridBadgeCandidates(
      index: idx,
      anchor: anchors[idx],
      badgeSize: bSize,
      context: context
    )
    let rects = candPoints.map {
      CGRect(
        origin: clampedGridBadgeOrigin($0, badgeSize: bSize, context: context),
        size: bSize
      )
    }
    let chosen: CGRect
    if let free = rects.first(where: {
      gridBadgeCollisions($0, ownIndex: idx, obstacles: obstacles, gridRect: gridRect) == 0
    }) {
      chosen = free
    } else {
      chosen = rects.min {
        gridBadgeCollisions($0, ownIndex: idx, obstacles: obstacles, gridRect: gridRect) <
          gridBadgeCollisions($1, ownIndex: idx, obstacles: obstacles, gridRect: gridRect)
      } ?? rects[0]
    }
    results[idx] = chosen
    obstacles.placedBadges.append(chosen)
  }

  return results
}

private struct GridBadgeContext {
  let gridRect: CGRect
  let viewSize: CGSize
  let topInset: CGFloat
  let margin: CGFloat
}

private func clampedGridBadgeOrigin(
  _ origin: CGPoint,
  badgeSize: CGSize,
  context: GridBadgeContext
) -> CGPoint {
  CGPoint(
    x: max(4, min(origin.x, context.viewSize.width - badgeSize.width - 4)),
    y: max(context.topInset + 4, min(origin.y, context.viewSize.height - badgeSize.height - 4))
  )
}

private func gridBadgeCollisions(
  _ rect: CGRect,
  ownIndex: Int,
  obstacles: BadgeObstacles,
  gridRect: CGRect
) -> Int {
  let anchorHits = obstacles.anchorRects.enumerated().filter { idx, aRect in
    idx != ownIndex && aRect.intersects(rect)
  }.count
  let badgeHits = obstacles.placedBadges.filter {
    $0.insetBy(dx: -2, dy: -2).intersects(rect)
  }.count
  let gridHits = gridRect.intersects(rect) ? 1 : 0
  return anchorHits * 2 + badgeHits * 3 + gridHits * 10
}

private func gridBadgeCandidates(
  index: Int,
  anchor: CGPoint,
  badgeSize: CGSize,
  context: GridBadgeContext
) -> [CGPoint] {
  if index == 4 {
    return centerGridBadgeCandidates(anchor: anchor, badgeSize: badgeSize, context: context)
  }
  return outerGridBadgeCandidates(index: index, anchor: anchor, badgeSize: badgeSize, context: context)
}

private func centerGridBadgeCandidates(
  anchor: CGPoint,
  badgeSize: CGSize,
  context: GridBadgeContext
) -> [CGPoint] {
  let gridRect = context.gridRect
  let margin = context.margin
  return [
    // Off-axis positions: angled away from cardinal (1, 3, 5, 7) and diagonal lines so lines never meld
    CGPoint(x: gridRect.midX + badgeSize.width / 2 + 4, y: gridRect.minY - (badgeSize.height + margin) * 2),
    CGPoint(x: gridRect.midX - badgeSize.width * 1.5 - 4, y: gridRect.minY - (badgeSize.height + margin) * 2),
    CGPoint(x: gridRect.midX + badgeSize.width / 2 + 4, y: gridRect.maxY + margin * 2 + badgeSize.height),
    CGPoint(x: gridRect.midX - badgeSize.width * 1.5 - 4, y: gridRect.maxY + margin * 2 + badgeSize.height),
    CGPoint(x: gridRect.maxX + margin * 2 + badgeSize.width, y: anchor.y - badgeSize.height - 4),
    CGPoint(x: gridRect.maxX + margin * 2 + badgeSize.width, y: anchor.y + 4),
    CGPoint(x: gridRect.minX - (badgeSize.width + margin) * 2, y: anchor.y - badgeSize.height - 4),
    CGPoint(x: gridRect.minX - (badgeSize.width + margin) * 2, y: anchor.y + 4)
  ]
}

private func outerGridBadgeCandidates(
  index: Int,
  anchor: CGPoint,
  badgeSize: CGSize,
  context: GridBadgeContext
) -> [CGPoint] {
  let gridRect = context.gridRect
  let margin = context.margin
  let col = index % 3
  let row = index / 3
  let primX: CGFloat
  let primY: CGFloat

  if col == 0 {
    primX = gridRect.minX - badgeSize.width - margin
  } else if col == 2 {
    primX = gridRect.maxX + margin
  } else {
    primX = anchor.x - badgeSize.width / 2
  }

  if row == 0 {
    primY = gridRect.minY - badgeSize.height - margin
  } else if row == 2 {
    primY = gridRect.maxY + margin
  } else {
    primY = anchor.y - badgeSize.height / 2
  }

  var list = [CGPoint(x: primX, y: primY)]

  if col == 0 {
    list.append(CGPoint(x: primX, y: anchor.y - badgeSize.height / 2))
    list.append(CGPoint(x: anchor.x - badgeSize.width / 2, y: gridRect.minY - badgeSize.height - margin))
  } else if col == 2 {
    list.append(CGPoint(x: primX, y: anchor.y - badgeSize.height / 2))
    list.append(CGPoint(x: anchor.x - badgeSize.width / 2, y: gridRect.minY - badgeSize.height - margin))
  }

  if gridRect.minX < badgeSize.width + margin {
    list.append(CGPoint(x: gridRect.maxX + margin, y: primY))
    list.append(CGPoint(x: gridRect.maxX + margin * 2 + badgeSize.width, y: primY))
  }
  if gridRect.maxX > context.viewSize.width - badgeSize.width - margin {
    list.append(CGPoint(x: gridRect.minX - badgeSize.width - margin, y: primY))
    list.append(CGPoint(x: gridRect.minX - (badgeSize.width + margin) * 2, y: primY))
  }
  if gridRect.minY < context.topInset + badgeSize.height + margin {
    list.append(CGPoint(x: primX, y: gridRect.maxY + margin))
    list.append(CGPoint(x: primX, y: gridRect.maxY + margin * 2 + badgeSize.height))
  }
  if gridRect.maxY > context.viewSize.height - badgeSize.height - margin {
    list.append(CGPoint(x: primX, y: gridRect.minY - badgeSize.height - margin))
    list.append(CGPoint(x: primX, y: gridRect.minY - (badgeSize.height + margin) * 2))
  }

  return list
}
