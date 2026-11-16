import CoreGraphics
import Foundation

extension LabelGenerator {
  /// Single-linkage components: an item joins a cluster when it's within
  /// collapsedClusterMaxGap of any member — clusters grow by adjacency.
  static func proximityComponents<T>(
    _ items: [T], frame: (T) -> CGRect
  ) -> [[T]] {
    var remaining = items
    var components: [[T]] = []
    while let seed = remaining.first {
      var component = [seed]
      remaining.removeFirst()
      while let position = remaining.firstIndex(where: { item in
        component.contains { frameGap(frame($0), frame(item)) <= collapsedClusterMaxGap }
      }) {
        component.append(remaining.remove(at: position))
      }
      components.append(component)
    }
    return components
  }

  static func frameGap(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let hGap = max(0, max(first.minX - second.maxX, second.minX - first.maxX))
    let vGap = max(0, max(first.minY - second.maxY, second.minY - first.maxY))
    return max(hGap, vGap)
  }

  /// collapsedGroups needs shared label prefixes, which text hints lack —
  /// dense clusters keep hierarchical labels so the signpost badge survives.
  static func assignClusterLabels(
    to labels: inout [String?], used: inout Set<String>, elements: [NavigationTarget]
  ) {
    guard elements.count > flatLabelLimit else { return }
    let clusters = collapsibleClusters(in: elements)
    guard clusters.memberIndices.count > 1 else { return }

    let prefixLength = comboLength(for: clusters.ancestors.count)
    var prefixIterator = sortedCombos(length: prefixLength).makeIterator()
    for memberIndices in clusters.memberIndices {
      guard let prefix = prefixIterator.next() else { break }
      let suffixLength = comboLength(for: memberIndices.count)
      var suffixIterator = sortedCombos(length: suffixLength).makeIterator()
      for index in memberIndices {
        guard let suffix = suffixIterator.next() else { break }
        let label = prefix + suffix
        guard !isBanned(label), !labelConflicts(label, with: used) else { continue }
        labels[index] = label
        used.insert(label)
      }
    }
  }

  static func collapsibleClusters(
    in elements: [NavigationTarget]
  ) -> (memberIndices: [[Int]], ancestors: [GroupingAncestor]) {
    var seen = Set<GroupingAncestor>()
    var order: [GroupingAncestor] = []
    for element in elements where seen.insert(element.groupingAncestor).inserted {
      order.append(element.groupingAncestor)
    }
    let small = elements.indices.filter {
      elements[$0].screenFrame.width <= collapsedClusterMaxExtent
        && elements[$0].screenFrame.height <= collapsedClusterMaxExtent
    }
    let dense = proximityRuns(small, in: elements)
    return (dense, order)
  }

  /// Splits same-ancestor members into proximity components, keeping
  /// runs of minCount+.
  static func proximityRuns(
    _ indices: [Int], in elements: [NavigationTarget]
  ) -> [[Int]] {
    var runs = proximityComponents(indices) { elements[$0].screenFrame }
      .filter { $0.count >= collapsedClusterMinCount }
    var memberSet = Set(runs.flatMap { $0 })
    var unions = runs.map { members in
      members.dropFirst().reduce(elements[members[0]].screenFrame) {
        $0.union(elements[$1].screenFrame)
      }
    }
    for index in elements.indices where !memberSet.contains(index) {
      let frame = elements[index].screenFrame
      let center = CGPoint(x: frame.midX, y: frame.midY)
      guard let runIndex = unions.firstIndex(where: { $0.contains(center) })
      else { continue }
      runs[runIndex].append(index)
      unions[runIndex] = unions[runIndex].union(frame)
      memberSet.insert(index)
    }
    return runs
  }
}
