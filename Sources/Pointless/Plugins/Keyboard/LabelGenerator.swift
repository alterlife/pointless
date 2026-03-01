import Foundation

// NOTE: DiscoveredElement is defined in AccessibilityScanner.swift (same module)

struct LabeledElement {
  let label: String
  let element: DiscoveredElement
}

enum LabelGenerator {
  /// Keyboard row priority: home row → top row → bottom row.
  /// Within each row, keys are ordered by distance from centre (most reachable first).
  static let priorityKeys: [Character] = [
    // Home row — strongest fingers first, then outward
    "a", "s", "d", "f", "j", "k", "l", "g", "h",
    // Top row
    "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
    // Bottom row
    "z", "x", "c", "v", "b", "n", "m"
  ]

  /// Assign labels to pre-sorted elements
  static func label(_ elements: [DiscoveredElement]) -> [LabeledElement] {
    let labels = makeLabels(count: elements.count)
    return zip(elements, labels).map { elem, lbl in LabeledElement(label: lbl, element: elem) }
  }

  /// Returns all if prefix empty; filtered subset otherwise
  static func filter(_ labeled: [LabeledElement], prefix: String) -> [LabeledElement] {
    guard !prefix.isEmpty else { return labeled }
    return labeled.filter { $0.label.hasPrefix(prefix) }
  }

  /// Returns nil if no exact match
  static func exactMatch(in labeled: [LabeledElement], for input: String) -> LabeledElement? {
    labeled.first { $0.label == input }
  }

  /// Single letters (26), then two-letter combos (aa, as, ad, ...) if needed
  private static func makeLabels(count: Int) -> [String] {
    guard count > 0 else { return [] }
    let keys = priorityKeys.map { String($0) }
    var labels = keys
    outer: for first in keys {
      for second in keys {
        labels.append(first + second)
        if labels.count >= count { break outer }
      }
    }
    return Array(labels.prefix(count))
  }
}
