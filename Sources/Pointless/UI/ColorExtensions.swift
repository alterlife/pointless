import SwiftUI

extension Color {
  init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    guard hexSanitized.count == 6 else { return nil }

    var rgb: UInt64 = 0
    let scanner = Scanner(string: hexSanitized)
    guard scanner.scanHexInt64(&rgb), scanner.isAtEnd else { return nil }

    let red = Double((rgb & 0xFF0000) >> 16) / 255.0
    let green = Double((rgb & 0x00FF00) >> 8) / 255.0
    let blue = Double(rgb & 0x0000FF) / 255.0

    self.init(red: red, green: green, blue: blue)
  }

  func toHex() -> String {
    guard let rgbColor = NSColor(self).usingColorSpace(.sRGB),
          let components = rgbColor.cgColor.components,
          components.count >= 3 else {
      return "#007AFF"
    }
    let red = max(0, min(255, Int((components[0] * 255.0).rounded())))
    let green = max(0, min(255, Int((components[1] * 255.0).rounded())))
    let blue = max(0, min(255, Int((components[2] * 255.0).rounded())))
    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}
