import Foundation

// NOTE: DiscoveredElement is defined in Discovery/DiscoveredElement.swift (same module)

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

  /// All labels have the same length — determined by how many elements need labelling.
  /// This eliminates prefix ambiguity (e.g. "a" vs "as").
  ///   ≤27 elements  → 1 char  (a, s, d, ...)
  ///   ≤729 elements → 2 chars (aa, as, ad, ...)
  ///   >729 elements → 3 chars (aaa, aas, ...)
  private static func makeLabels(count: Int) -> [String] {
    guard count > 0 else { return [] }
    let keys = priorityKeys.map { String($0) }
    let base = keys.count

    // Determine the uniform label length needed
    let length: Int
    if count <= base {
      length = 1
    } else if count <= base * base {
      length = 2
    } else {
      length = 3
    }

    var labels: [String] = []
    generateCombinations(keys: keys, length: length, current: "", into: &labels, needed: count)
    return labels
  }

  private static func generateCombinations(
    keys: [String], length: Int, current: String, into labels: inout [String], needed: Int
  ) {
    if current.count == length {
      labels.append(current)
      return
    }
    for key in keys {
      if labels.count >= needed { return }
      generateCombinations(keys: keys, length: length, current: current + key, into: &labels, needed: needed)
    }
  }
}
