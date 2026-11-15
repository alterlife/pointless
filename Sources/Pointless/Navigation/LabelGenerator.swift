import CoreGraphics
import Foundation

// NOTE: NavigationTarget is defined in Discovery/NavigationTarget.swift (same module)

struct LabeledElement {
  let label: String
  let element: NavigationTarget
}

/// A dense cluster of small siblings collapsed into one signpost badge.
/// Members keep their labels but render faint until the shared prefix is typed.
struct CollapsedGroup {
  let prefix: String
  let label: String
  let frame: CGRect
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

  enum LabelStrategy {
    case homerowKeys
    case clickableElementText
  }

  private static let collapsedClusterMinCount = 6
  private static let collapsedClusterMaxExtent: CGFloat = 56

  /// Assign labels to pre-sorted elements
  static func label(
    _ elements: [NavigationTarget], strategy: LabelStrategy = .homerowKeys
  ) -> [LabeledElement] {
    // Text hints are self-describing — group prefixes add nothing, so the
    // text strategy stays flat at any count.
    guard strategy == .homerowKeys,
          elements.count > flatLabelLimit,
          let groups = labelGroups(for: elements)
    else {
      return flatLabel(elements, strategy: strategy)
    }
    return hierarchicalLabel(elements, groups: groups, strategy: strategy)
  }

  /// Dense clusters of small siblings get a signpost badge; members stay
  /// labeled but render faint until their shared prefix is typed.
  static func collapsedGroups(in labeled: [LabeledElement]) -> [CollapsedGroup] {
    guard labeled.count > flatLabelLimit else { return [] }
    let ancestorCount = Set(labeled.map { $0.element.groupingAncestor }).count
    guard ancestorCount > 1 else { return [] }
    let prefixLength = comboLength(for: ancestorCount)

    var membersByPrefix: [String: [LabeledElement]] = [:]
    var prefixOrder: [String] = []
    for item in labeled {
      let prefix = String(item.label.prefix(prefixLength))
      if membersByPrefix[prefix] == nil { prefixOrder.append(prefix) }
      membersByPrefix[prefix, default: []].append(item)
    }

    return prefixOrder.compactMap { prefix in
      let members = membersByPrefix[prefix] ?? []
      guard members.count >= collapsedClusterMinCount,
            members.allSatisfy({
              $0.element.groupingAncestor == members[0].element.groupingAncestor
                && $0.element.screenFrame.width <= collapsedClusterMaxExtent
                && $0.element.screenFrame.height <= collapsedClusterMaxExtent
            })
      else { return nil }
      let frame = members.dropFirst().reduce(members[0].element.screenFrame) {
        $0.union($1.element.screenFrame)
      }
      return CollapsedGroup(
        prefix: prefix, label: "\(prefix)_ (\(members.count) items)", frame: frame
      )
    }
  }

  /// First-appearance order — earlier groups get the home-row prefixes.
  private static func labelGroups(
    for elements: [NavigationTarget]
  ) -> [(ancestor: GroupingAncestor, indices: [Int])]? {
    var order: [GroupingAncestor] = []
    var indexByGroup: [GroupingAncestor: [Int]] = [:]
    for (index, element) in elements.enumerated() {
      if indexByGroup[element.groupingAncestor] == nil { order.append(element.groupingAncestor) }
      indexByGroup[element.groupingAncestor, default: []].append(index)
    }
    guard order.count > 1 else { return nil }
    return order.map { (ancestor: $0, indices: indexByGroup[$0] ?? []) }
  }

  private static func flatLabel(
    _ elements: [NavigationTarget], strategy: LabelStrategy
  ) -> [LabeledElement] {
    var labels = [String?](repeating: nil, count: elements.count)
    var used = Set<String>()
    if strategy == .clickableElementText {
      for (index, element) in elements.enumerated() {
        if let hint = textHint(for: element.text, avoiding: used) {
          labels[index] = hint
          used.insert(hint)
        }
      }
    }
    var pool = sortedCombos(length: comboLength(for: elements.count))
      .filter { !used.contains($0) }
      .makeIterator()
    for index in elements.indices where labels[index] == nil {
      labels[index] = pool.next()
    }
    return zip(elements, labels.compactMap { $0 }).map { elem, lbl in
      LabeledElement(label: lbl, element: elem)
    }
  }

  /// Shortest unique prefix (2–4 chars) of the element's visible text.
  /// "Save" → "sav", "Save File" colliding → "savef". Nil when unusable.
  private static func textHint(for text: String, avoiding used: Set<String>) -> String? {
    let stream = text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined()
    guard stream.count >= 2 else { return nil }
    // Prefer 3 chars (readable), extend to 4 on collision, 2 as last resort.
    let lengths = [3, 4, 2].filter { $0 <= stream.count }
    for length in lengths {
      let candidate = String(stream.prefix(length))
      if !used.contains(candidate), !isBanned(candidate) { return candidate }
    }
    return nil
  }

  private static func hierarchicalLabel(
    _ elements: [NavigationTarget],
    groups: [(ancestor: GroupingAncestor, indices: [Int])],
    strategy: LabelStrategy
  ) -> [LabeledElement] {
    let prefixLength = comboLength(for: groups.count)
    let prefixes = combos(count: groups.count, length: prefixLength)
    var result = [LabeledElement?](repeating: nil, count: elements.count)
    for (groupIndex, cluster) in groups.enumerated() {
      let prefix = prefixes[groupIndex]
      let suffixLength = comboLength(for: cluster.indices.count)
      let candidates = sortedCombos(length: suffixLength)
      var candidateIndex = 0
      for elementIndex in cluster.indices {
        // Banned words can span the prefix/suffix boundary ("a" + "ss"), so
        // check the full label and skip offending suffixes.
        while candidateIndex < candidates.count, isBanned(prefix + candidates[candidateIndex]) {
          candidateIndex += 1
        }
        guard candidateIndex < candidates.count else {
          return flatLabel(elements, strategy: strategy)
        }
        result[elementIndex] = LabeledElement(
          label: prefix + candidates[candidateIndex],
          element: elements[elementIndex]
        )
        candidateIndex += 1
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
    Array(sortedCombos(length: length).prefix(count))
  }

  /// Every combo of `length` chars in preference order, minus banned words.
  private static func sortedCombos(length: Int) -> [String] {
    if length == 1 {
      return priorityKeys.map(String.init)
    }
    let keys = priorityKeys.map { String($0) }
    var generated: [String] = []
    generateCombinations(keys: keys, length: length, current: "", into: &generated, needed: .max)
    let allowed = generated.filter { !isBanned($0) }
    let homeRowCount = 9
    let indexOf = Dictionary(uniqueKeysWithValues: priorityKeys.enumerated().map { ($0.element, $0.offset) })
    // Score packs (non-home-row count, priority-index sum) into one Int —
    // index sums stay under 10_000 for lengths ≤ 3. Ties sort by char index
    // last-to-first so consecutive combos differ in the first char — spatial
    // neighbors get labels one keystroke apart (Vimium-style).
    struct Candidate {
      let score: Int
      let combo: String
      let indices: [Int]
    }
    let scored = allowed.map { combo -> Candidate in
      var nonHome = 0
      var indexSum = 0
      var indices: [Int] = []
      for char in combo {
        let index = indexOf[char] ?? 0
        indices.append(index)
        indexSum += index
        if index >= homeRowCount { nonHome += 1 }
      }
      return Candidate(score: nonHome * 10_000 + indexSum, combo: combo, indices: indices)
    }.sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      return lhs.indices.reversed().lexicographicallyPrecedes(rhs.indices.reversed())
    }
    return scored.map(\.combo)
  }

  private static func isBanned(_ label: String) -> Bool {
    BannedLabelWords.all.contains { label.contains($0) }
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
