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

  /// Past this, flat labels need 2 chars anyway — hierarchical costs the same
  /// keystrokes and narrows faster.
  private static let flatLabelLimit = 27

  /// Assign labels to pre-sorted elements
  static func label(_ elements: [DiscoveredElement]) -> [LabeledElement] {
    guard elements.count > flatLabelLimit, let groups = labelGroups(for: elements) else {
      return flatLabel(elements)
    }
    return hierarchicalLabel(elements, groups: groups)
  }

  /// First-appearance order — earlier groups get the home-row prefixes.
  private static func labelGroups(for elements: [DiscoveredElement]) -> [(group: DiscoveryGroup, indices: [Int])]? {
    var order: [DiscoveryGroup] = []
    var indexByGroup: [DiscoveryGroup: [Int]] = [:]
    for (index, element) in elements.enumerated() {
      if indexByGroup[element.group] == nil { order.append(element.group) }
      indexByGroup[element.group, default: []].append(index)
    }
    guard order.count > 1 else { return nil }
    return order.map { (group: $0, indices: indexByGroup[$0] ?? []) }
  }

  private static func flatLabel(_ elements: [DiscoveredElement]) -> [LabeledElement] {
    let labels = combos(count: elements.count, length: comboLength(for: elements.count))
    return zip(elements, labels).map { elem, lbl in LabeledElement(label: lbl, element: elem) }
  }

  private static func hierarchicalLabel(
    _ elements: [DiscoveredElement],
    groups: [(group: DiscoveryGroup, indices: [Int])]
  ) -> [LabeledElement] {
    let prefixLength = comboLength(for: groups.count)
    let prefixes = combos(count: groups.count, length: prefixLength)
    var result = [LabeledElement?](repeating: nil, count: elements.count)
    for (groupIndex, group) in groups.enumerated() {
      let suffixLength = comboLength(for: group.indices.count)
      let suffixes = combos(count: group.indices.count, length: suffixLength)
      for (itemIndex, elementIndex) in group.indices.enumerated() {
        result[elementIndex] = LabeledElement(
          label: prefixes[groupIndex] + suffixes[itemIndex],
          element: elements[elementIndex]
        )
      }
    }
    return result.compactMap { $0 }
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

  private static func comboLength(for count: Int) -> Int {
    let base = priorityKeys.count
    if count <= base { return 1 }
    if count <= base * base { return 2 }
    return 3
  }

  /// Combos using only home-row keys come first, then one non-home-row key, etc.
  private static func combos(count: Int, length: Int) -> [String] {
    if length == 1 {
      return priorityKeys.prefix(count).map(String.init)
    }
    let keys = priorityKeys.map { String($0) }
    var all: [String] = []
    generateCombinations(keys: keys, length: length, current: "", into: &all, needed: .max)
    let homeRowCount = 9
    let indexOf = Dictionary(uniqueKeysWithValues: priorityKeys.enumerated().map { ($0.element, $0.offset) })
    // Score packs (non-home-row count, priority-index sum) into one Int —
    // index sums stay under 10_000 for lengths ≤ 3.
    let scored = all.enumerated().map { offset, combo -> (Int, Int) in
      var nonHome = 0
      var indexSum = 0
      for char in combo {
        let index = indexOf[char] ?? 0
        indexSum += index
        if index >= homeRowCount { nonHome += 1 }
      }
      return (nonHome * 10_000 + indexSum, offset)
    }.sorted { lhs, rhs in
      lhs.0 != rhs.0 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
    }
    return scored.prefix(count).map { all[$0.1] }
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
