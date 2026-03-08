import Combine
import Foundation
import OSLog
import SwiftUI

/// CPU monitoring plugin with full configurability
class CPUPlugin: NSObject, ObservableObject, Plugin {
  let id = "pointless.cpu"
  let name = "CPU"
  let icon = "cpu"

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

  var totalUsage: Double = 0.0
  var coreUsages: [Double] = []
  var history: [Double] = []
  var coreHistories: [[Double]] = []
  let maxHistorySize = 30

  var previousCPUInfo: [Int32] = []

  override init() {
    super.init()
    initialize()
  }

  func initialize() {
    declareSettings([
      .section(label: "Display"),
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
      .section(label: "CPU Cores"),
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
      .section(label: "Color"),
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
      .section(label: "General"),
      .toggle(
        key: "enabled",
        label: "Enabled",
        defaultValue: true
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
      MenuWidget(id: "\(id).detail", pluginId: id, name: "CPU Details", priority: 10) {
        self.detailContentView()
      }
    ]
  }

  func detailView() -> AnyView {
    AnyView(detailContentView())
  }

  @ViewBuilder
  private func detailContentView() -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if showCores && !coreUsages.isEmpty {
        coreViews()
      } else {
        HStack(spacing: 6) {
          if showIcon {
            Image(systemName: "cpu")
              .font(.title2)
              .foregroundColor(primaryColor())
          }
          if displayMode == "text" || displayMode == "both" {
            textView(usage: totalUsage)
          }
        }
        if displayMode == "graph" || displayMode == "both" {
          graphView(history: history, usage: totalUsage, label: nil)
        }
      }

      if showUpdateText {
        Text("Updates every \(String(format: "%.0f", updateInterval))s")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding()
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
    let coreColors = coreHistories.indices.map { coreColor(for: $0) }
    VStack(alignment: .leading, spacing: 8) {
      if displayMode == "text" || displayMode == "both" {
        textView(usage: totalUsage)
      }
      if displayMode == "graph" || displayMode == "both" {
        CPUGraphView(histories: coreHistories, usage: totalUsage, colors: coreColors, compact: false)
      }
    }
  }
}
