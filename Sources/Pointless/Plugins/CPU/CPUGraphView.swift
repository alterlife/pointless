import SwiftUI

struct CPUGraphView: View {
  let history: [Double]
  let usage: Double
  let label: String?
  let color: Color
  let compact: Bool

  init(history: [Double], usage: Double, label: String? = nil, color: Color, compact: Bool = false) {
    self.history = history
    self.usage = usage
    self.label = label
    self.color = color
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
        let points = history.enumerated().map { index, value in
          let xPos = width * CGFloat(index) / CGFloat(max(history.count - 1, 1))
          let yPos = height * (1 - CGFloat(value))
          return CGPoint(x: xPos, y: yPos)
        }

        ZStack(alignment: .bottomLeading) {
          Path { path in
            for row in stride(from: 0, through: 4, by: 1) {
              let yPos = height * CGFloat(row) / 4
              path.move(to: CGPoint(x: 0, y: yPos))
              path.addLine(to: CGPoint(x: width, y: yPos))
            }
          }
          .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)

          Path { path in
            guard !points.isEmpty, let lastPoint = points.last else { return }
            path.move(to: CGPoint(x: points[0].x, y: height))
            path.addLine(to: points[0])
            for point in points {
              path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: lastPoint.x, y: height))
            path.closeSubpath()
          }
          .fill(
            LinearGradient(
              colors: [
                color.opacity(0.3),
                color.opacity(0.05)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )

          Path { path in
            guard !points.isEmpty else { return }
            path.move(to: points[0])
            for point in points {
              path.addLine(to: point)
            }
          }
          .stroke(color, lineWidth: compact ? 1.5 : 2)

          if let lastPoint = points.last {
            Circle()
              .fill(color)
              .frame(width: compact ? 4 : 6, height: compact ? 4 : 6)
              .position(lastPoint)
          }
        }
      }
      .frame(height: compact ? 30 : 60)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(4)
    }
  }
}
