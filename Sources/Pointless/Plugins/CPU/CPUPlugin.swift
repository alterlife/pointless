import Combine
import Foundation
import OSLog
import SwiftUI

/// CPU monitoring plugin with full configurability
class CPUPlugin: NSObject, ObservableObject, Plugin {
  let id = "pointless.cpu"
  let name = "CPU"

  @Published var menuBarText: String = "CPU --"
  @Published var isEnabled: Bool = true
  @Published var updateInterval: TimeInterval = 2.0
  @Published var displayMode: String = "both"
  @Published var showIcon: Bool = true
  @Published var showUpdateText: Bool = true
  @Published var showCores: Bool = false
  @Published var coreLayout: String = "separate"
  @Published var colorMode: String = "dynamic"
  @Published var customColor: String = "#007AFF"

  private var totalUsage: Double = 0.0
  private var coreUsages: [Double] = []
  private var history: [Double] = []
  private var coreHistories: [[Double]] = []
  private let maxHistorySize = 30

  private var previousCPUInfo: [Int32] = []

  override init() {
    super.init()
    initialize()
  }

  func initialize() {
    declareSettings([
      .toggle(
        key: "enabled",
        label: "Enabled",
        defaultValue: true
      ),
      .dropdown(
        key: "displayMode",
        label: "Display Mode",
        options: ["text", "graph", "both"],
        defaultValue: "both"
      ),
      .toggle(
        key: "showIcon",
        label: "Show Icon",
        defaultValue: true
      ),
      .toggle(
        key: "showUpdateText",
        label: "Show Update Interval",
        defaultValue: true
      ),
      .toggle(
        key: "showCores",
        label: "Show Individual Cores",
        defaultValue: false
      ),
      .dropdown(
        key: "coreLayout",
        label: "Core Layout",
        options: ["combined", "separate"],
        defaultValue: "separate"
      ),
      .dropdown(
        key: "colorMode",
        label: "Color Mode",
        options: ["dynamic", "custom"],
        defaultValue: "dynamic"
      ),
      .color(
        key: "customColor",
        label: "Custom Color",
        defaultValue: "#007AFF"
      ),
      .slider(
        key: "updateInterval",
        label: "Update Interval (seconds)",
        range: 1.0...60.0,
        defaultValue: 2.0,
        step: 1.0
      )
    ])

    setupPeriodicUpdate(interval: \.updateInterval) { [weak self] in
      self?.refresh()
    }
  }

  private func refresh() {
    let cpuData = currentUsage()
    totalUsage = cpuData.total
    coreUsages = cpuData.perCore

    menuBarText = String(format: "CPU %.0f%%", totalUsage * 100)

    history.append(totalUsage)
    if history.count > maxHistorySize {
      history.removeFirst()
    }

    // Track per-core history
    for (index, coreUsage) in coreUsages.enumerated() {
      while coreHistories.count <= index {
        coreHistories.append([])
      }
      coreHistories[index].append(coreUsage)
      if coreHistories[index].count > maxHistorySize {
        coreHistories[index].removeFirst()
      }
    }

    Logger.debug("CPU: \(String(format: "%.1f%%", totalUsage * 100))")
  }

  func configure(_ values: [String: Any]) {
    if let enabled = values["enabled"] as? Bool {
      isEnabled = enabled
    }
    if let mode = values["displayMode"] as? String {
      displayMode = mode
    }
    if let icon = values["showIcon"] as? Bool {
      showIcon = icon
    }
    if let updateText = values["showUpdateText"] as? Bool {
      showUpdateText = updateText
    }
    if let cores = values["showCores"] as? Bool {
      showCores = cores
    }
    if let layout = values["coreLayout"] as? String {
      coreLayout = layout
    }
    if let mode = values["colorMode"] as? String {
      colorMode = mode
    }
    if let color = values["customColor"] as? String {
      customColor = color
    }
    if let interval = values["updateInterval"] as? TimeInterval {
      updateInterval = interval
    }
    saveSettings(values)
  }

  // MARK: - Widget System

  func menuBarWidgets() -> [MenuBarWidget] {
    [
      MenuBarWidget(
        id: "\(id).menubar",
        pluginId: id,
        name: "CPU Status",
        priority: 10
      ) {
        HStack(spacing: 4) {
          if self.showIcon {
            Image(systemName: "cpu")
              .font(.system(size: 11))
              .foregroundColor(self.primaryColor())
          }
          Text(String(format: "%.0f%%", self.totalUsage * 100))
            .font(.system(size: 12))
        }
      }
    ]
  }

  func menuWidgets() -> [MenuWidget] {
    [
      MenuWidget(
        id: "\(id).detail",
        pluginId: id,
        name: "CPU Details",
        priority: 10
      ) {
        VStack(alignment: .leading, spacing: 12) {
          if self.showIcon {
            Image(systemName: "cpu")
              .font(.title2)
              .foregroundColor(self.primaryColor())
          }

          if self.showCores && !self.coreUsages.isEmpty {
            self.coreViews()
          } else {
            self.totalViews()
          }

          if self.showUpdateText {
            Text("Updates every \(String(format: "%.0f", self.updateInterval))s")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding()
      }
    ]
  }

  // MARK: - Legacy Views

  func detailView() -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 12) {
        if showIcon {
          Image(systemName: "cpu")
            .font(.title2)
            .foregroundColor(primaryColor())
        }

        if showCores && !coreUsages.isEmpty {
          coreViews()
        } else {
          totalViews()
        }

        if showUpdateText {
          Text("Updates every \(String(format: "%.0f", updateInterval))s")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding()
    )
  }

  @ViewBuilder
  private func totalViews() -> some View {
    switch displayMode {
    case "text":
      textView(usage: totalUsage)
    case "graph":
      graphView(history: history, usage: totalUsage, label: nil)
    default: // "both"
      textView(usage: totalUsage)
      graphView(history: history, usage: totalUsage, label: nil)
    }
  }

  @ViewBuilder
  private func coreViews() -> some View {
    if coreLayout == "combined" {
      combinedCoresView()
    } else {
      separateCoresView()
    }
  }

  @ViewBuilder
  private func combinedCoresView() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      textView(usage: totalUsage)

      if displayMode == "graph" || displayMode == "both" {
        graphView(history: history, usage: totalUsage, label: nil)
      }
    }
  }

  @ViewBuilder
  private func separateCoresView() -> some View {
    switch displayMode {
    case "text":
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(coreUsages.enumerated()), id: \.offset) { [self] index, usage in
          HStack {
            Text("Core \(index + 1)")
              .font(.caption)
              .foregroundColor(.secondary)
              .frame(width: 50, alignment: .leading)
            self.textView(usage: usage, compact: true)
          }
        }
      }
    case "graph":
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(coreHistories.enumerated()), id: \.offset) { [self] index, coreHistory in
          if index < self.coreUsages.count {
            self.graphView(
              history: coreHistory,
              usage: self.coreUsages[index],
              label: "Core \(index + 1)",
              compact: true
            )
          }
        }
      }
    default: // "both"
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(coreUsages.enumerated()), id: \.offset) { [self] index, usage in
          if index < self.coreHistories.count {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("Core \(index + 1)")
                  .font(.caption)
                  .foregroundColor(.secondary)
                textView(usage: usage, compact: true)
              }
              graphView(
                history: self.coreHistories[index],
                usage: usage,
                label: nil,
                compact: true
              )
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func textView(usage: Double, compact: Bool = false) -> some View {
    Text(String(format: "%.1f%%", usage * 100))
      .font(compact ? .body : .title3)
      .foregroundColor(usageColor(for: usage))
  }

  @ViewBuilder
  private func graphView(
    history: [Double],
    usage: Double,
    label: String?,
    compact: Bool = false
  ) -> some View {
    CPUGraphView(
      history: history,
      usage: usage,
      label: label,
      color: usageColor(for: usage),
      compact: compact
    )
  }

  private func primaryColor() -> Color {
    if colorMode == "custom" {
      return Color(hex: customColor) ?? .blue
    }
    return usageColor(for: totalUsage)
  }

  private func usageColor(for usage: Double) -> Color {
    if colorMode == "custom" {
      return Color(hex: customColor) ?? .blue
    }

    // Dynamic mode: color changes based on usage
    switch usage {
    case 0..<0.5:
      return .green
    case 0.5..<0.75:
      return .orange
    default:
      return .red
    }
  }

  // MARK: - CPU Usage

  private func currentUsage() -> (total: Double, perCore: [Double]) {
    var cpuInfo: processor_info_array_t?
    var numCPUInfo: mach_msg_type_number_t = 0
    var numProcessors: natural_t = 0

    let result = host_processor_info(
      mach_host_self(),
      PROCESSOR_CPU_LOAD_INFO,
      &numProcessors,
      &cpuInfo,
      &numCPUInfo
    )

    guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
      return (0.0, [])
    }

    // Copy current CPU info
    let currentCPUInfo = Array(UnsafeBufferPointer(
      start: cpuInfo,
      count: Int(numCPUInfo)
    ))

    defer {
      vm_deallocate(
        mach_task_self_,
        vm_address_t(UInt(bitPattern: cpuInfo)),
        vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)
      )
    }

    var perCoreUsage: [Double] = []
    var totalUsage: Double = 0.0

    // Initialize previous CPU info if needed
    if previousCPUInfo.isEmpty {
      previousCPUInfo = currentCPUInfo
      return (0.0, Array(repeating: 0.0, count: Int(numProcessors)))
    }

    for core in 0..<Int(numProcessors) {
      let offset = Int(CPU_STATE_MAX) * core

      // Current ticks
      let user = currentCPUInfo[offset + Int(CPU_STATE_USER)]
      let system = currentCPUInfo[offset + Int(CPU_STATE_SYSTEM)]
      let idle = currentCPUInfo[offset + Int(CPU_STATE_IDLE)]
      let nice = currentCPUInfo[offset + Int(CPU_STATE_NICE)]

      // Previous ticks
      let prevUser = previousCPUInfo[offset + Int(CPU_STATE_USER)]
      let prevSystem = previousCPUInfo[offset + Int(CPU_STATE_SYSTEM)]
      let prevIdle = previousCPUInfo[offset + Int(CPU_STATE_IDLE)]
      let prevNice = previousCPUInfo[offset + Int(CPU_STATE_NICE)]

      // Calculate deltas
      let userDelta = Double(user - prevUser)
      let systemDelta = Double(system - prevSystem)
      let idleDelta = Double(idle - prevIdle)
      let niceDelta = Double(nice - prevNice)

      let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
      let usage = totalDelta > 0 ? (userDelta + systemDelta + niceDelta) / totalDelta : 0.0

      perCoreUsage.append(usage)
      totalUsage += usage
    }

    // Store current values for next iteration
    previousCPUInfo = currentCPUInfo

    // Average total usage across all cores
    totalUsage = numProcessors > 0 ? totalUsage / Double(numProcessors) : 0.0

    return (totalUsage, perCoreUsage)
  }
}
