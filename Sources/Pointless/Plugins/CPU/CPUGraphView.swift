import SwiftUI

struct CPUGraphView: View {
  let histories: [[Double]]
  let usage: Double
  let label: String?
  let colors: [Color]
  let compact: Bool

  /// Single-history convenience init (fills under the line)
  init(history: [Double], usage: Double, label: String? = nil, color: Color, compact: Bool = false) {
    self.histories = [history]
    self.usage = usage
    self.label = label
    self.colors = [color]
    self.compact = compact
  }

  /// Multi-history init — one distinct color per line
  init(histories: [[Double]], usage: Double, label: String? = nil, colors: [Color], compact: Bool = false) {
    self.histories = histories
    self.usage = usage
    self.label = label
    self.colors = colors
    self.compact = compact
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let label = label {
        Text(label)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      GeometryReader { geometry in
        let width = geometry.size.width
        let height = geometry.size.height

        ZStack(alignment: .bottomLeading) {
          gridLines(width: width, height: height)

          if histories.count == 1 {
            singleHistoryGraph(width: width, height: height, history: histories[0])
          } else {
            multiHistoryGraph(width: width, height: height)
          }
        }
      }
      .frame(height: compact ? 30 : 60)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(4)
    }
  }

  private func points(for history: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
    history.enumerated().map { index, value in
      CGPoint(
        x: width * CGFloat(index) / CGFloat(max(history.count - 1, 1)),
        y: height * (1 - CGFloat(value))
      )
    }
  }

  @ViewBuilder
  private func gridLines(width: CGFloat, height: CGFloat) -> some View {
    Path { path in
      for row in stride(from: 0, through: 4, by: 1) {
        let yPos = height * CGFloat(row) / 4
        path.move(to: CGPoint(x: 0, y: yPos))
        path.addLine(to: CGPoint(x: width, y: yPos))
      }
    }
    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
  }

  @ViewBuilder
  private func singleHistoryGraph(width: CGFloat, height: CGFloat, history: [Double]) -> some View {
    let color = colors[0]
    let pts = points(for: history, width: width, height: height)

    Path { path in
      guard !pts.isEmpty, let lastPoint = pts.last else { return }
      path.move(to: CGPoint(x: pts[0].x, y: height))
      path.addLine(to: pts[0])
      for point in pts { path.addLine(to: point) }
      path.addLine(to: CGPoint(x: lastPoint.x, y: height))
      path.closeSubpath()
    }
    .fill(LinearGradient(
      colors: [color.opacity(0.3), color.opacity(0.05)],
      startPoint: .top,
      endPoint: .bottom
    ))

    Path { path in
      guard !pts.isEmpty else { return }
      path.move(to: pts[0])
      for point in pts { path.addLine(to: point) }
    }
    .stroke(color, lineWidth: compact ? 1.5 : 2)

    if let lastPoint = pts.last {
      Circle()
        .fill(color)
        .frame(width: compact ? 4 : 6, height: compact ? 4 : 6)
        .position(lastPoint)
    }
  }

  @ViewBuilder
  private func multiHistoryGraph(width: CGFloat, height: CGFloat) -> some View {
    ForEach(Array(histories.indices), id: \.self) { index in
      Path { path in
        let hist = histories[index]
        let pts = hist.enumerated().map { idx, value in
          CGPoint(
            x: width * CGFloat(idx) / CGFloat(max(hist.count - 1, 1)),
            y: height * (1 - CGFloat(value))
          )
        }
        guard !pts.isEmpty else { return }
        path.move(to: pts[0])
        for point in pts { path.addLine(to: point) }
      }
      .stroke(colors[index % colors.count].opacity(0.85), lineWidth: compact ? 1 : 1.5)
    }
  }
}
