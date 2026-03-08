import Foundation
import SwiftUI

// MARK: - View Helpers

extension CPUPlugin {
  @ViewBuilder
  func textView(usage: Double, compact: Bool = false, color: Color? = nil) -> some View {
    Text(String(format: "%.1f%%", usage * 100))
      .font(compact ? .body : .title3)
      .foregroundColor(color ?? usageColor(for: usage))
  }

  @ViewBuilder
  func graphView(history: [Double], usage: Double, label: String?, compact: Bool = false, color: Color? = nil)
  -> some View {
    CPUGraphView(
      history: history,
      usage: usage,
      label: label,
      color: color ?? usageColor(for: usage),
      compact: compact
    )
  }
}

// MARK: - Separate Cores View

extension CPUPlugin {
  @ViewBuilder
  func separateCoresView() -> some View {
    switch displayMode {
    case "text":
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(coreUsages.enumerated()), id: \.offset) { [self] index, usage in
          HStack {
            Text("Core \(index + 1)")
              .font(.caption)
              .foregroundColor(.secondary)
              .frame(width: 50, alignment: .leading)
            self.textView(usage: usage, compact: true, color: coreColor(for: index))
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
              compact: true,
              color: coreColor(for: index)
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
                textView(usage: usage, compact: true, color: coreColor(for: index))
              }
              graphView(
                history: self.coreHistories[index],
                usage: usage,
                label: nil,
                compact: true,
                color: coreColor(for: index)
              )
            }
          }
        }
      }
    }
  }
}

// MARK: - Core Colors

extension CPUPlugin {
  private static let corePalette: [Color] = [
    Color(hue: 0.60, saturation: 0.75, brightness: 0.95), // blue
    Color(hue: 0.35, saturation: 0.75, brightness: 0.85), // green
    Color(hue: 0.08, saturation: 0.90, brightness: 0.95), // orange
    Color(hue: 0.77, saturation: 0.70, brightness: 0.95), // purple
    Color(hue: 0.50, saturation: 0.75, brightness: 0.85), // teal
    Color(hue: 0.93, saturation: 0.80, brightness: 0.90), // pink
    Color(hue: 0.14, saturation: 0.90, brightness: 0.95), // yellow
    Color(hue: 0.67, saturation: 0.70, brightness: 0.90) // indigo
  ]

  func coreColor(for index: Int) -> Color {
    CPUPlugin.corePalette[index % CPUPlugin.corePalette.count]
  }
}

// MARK: - Color Helpers

extension CPUPlugin {
  func primaryColor() -> Color {
    usageColor(for: totalUsage)
  }

  func usageColor(for usage: Double) -> Color {
    if colorMode == "custom" {
      return Color(hex: customColor) ?? .blue
    }
    switch usage {
    case 0..<0.5:
      return .green
    case 0.5..<0.75:
      return .orange
    default:
      return .red
    }
  }
}

// MARK: - CPU Usage Reading

extension CPUPlugin {
  func currentUsage() -> (total: Double, perCore: [Double]) {
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

    let currentCPUInfo = Array(UnsafeBufferPointer(start: cpuInfo, count: Int(numCPUInfo)))

    defer {
      vm_deallocate(
        mach_task_self_,
        vm_address_t(UInt(bitPattern: cpuInfo)),
        vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)
      )
    }

    if previousCPUInfo.isEmpty {
      previousCPUInfo = currentCPUInfo
      return (0.0, Array(repeating: 0.0, count: Int(numProcessors)))
    }

    var perCoreUsage: [Double] = []
    var coreTotal: Double = 0.0

    for core in 0..<Int(numProcessors) {
      let offset = Int(CPU_STATE_MAX) * core
      let user = currentCPUInfo[offset + Int(CPU_STATE_USER)]
      let system = currentCPUInfo[offset + Int(CPU_STATE_SYSTEM)]
      let idle = currentCPUInfo[offset + Int(CPU_STATE_IDLE)]
      let nice = currentCPUInfo[offset + Int(CPU_STATE_NICE)]
      let prevUser = previousCPUInfo[offset + Int(CPU_STATE_USER)]
      let prevSystem = previousCPUInfo[offset + Int(CPU_STATE_SYSTEM)]
      let prevIdle = previousCPUInfo[offset + Int(CPU_STATE_IDLE)]
      let prevNice = previousCPUInfo[offset + Int(CPU_STATE_NICE)]

      let userDelta = Double(user - prevUser)
      let systemDelta = Double(system - prevSystem)
      let idleDelta = Double(idle - prevIdle)
      let niceDelta = Double(nice - prevNice)
      let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
      let usage = totalDelta > 0 ? (userDelta + systemDelta + niceDelta) / totalDelta : 0.0

      perCoreUsage.append(usage)
      coreTotal += usage
    }

    previousCPUInfo = currentCPUInfo
    let avgUsage = numProcessors > 0 ? coreTotal / Double(numProcessors) : 0.0
    return (avgUsage, perCoreUsage)
  }
}
