import Combine
import Foundation
import OSLog
import SwiftUI

/// CPU monitoring plugin - using protocol extension helpers
class CPUPlugin: NSObject, ObservableObject, Plugin {
  let id = "pointless.cpu"
  let name = "CPU"

  @Published var menuBarText: String = "CPU --"
  @Published var updateInterval: TimeInterval = 2.0

  private var cpuUsage: Double = 0.0

  override init() {
    super.init()
    initialize()
  }

  func initialize() {
    settings([
      .slider(
        key: "updateInterval",
        label: "Update Interval (seconds)",
        range: 1.0...60.0,
        defaultValue: 2.0
      )
    ])

    periodicUpdate(interval: \.updateInterval) { [weak self] in
      self?.update()
    }
  }

  private func update() {
    cpuUsage = getCPUUsage()
    menuBarText = String(format: "CPU %.0f%%", cpuUsage * 100)
    Logger.debug("CPU updated: \(String(format: "%.1f%%", cpuUsage * 100))")
  }

  func detailView() -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "cpu")
          Text(name)
            .font(.headline)
        }
        Text(String(format: "%.1f%%", cpuUsage * 100))
          .font(.system(.title, design: .monospaced))
        Text("Updates every \(String(format: "%.1f", updateInterval))s")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding()
    )
  }

  // MARK: - CPU Usage

  private func getCPUUsage() -> Double {
    var totalUsageOfCPU: Double = 0.0
    var threadsList: thread_act_array_t?
    var threadsCount = mach_msg_type_number_t(0)
    let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)

    if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
      for index in 0..<threadsCount {
        var threadInfo = thread_basic_info()
        var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
        let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
          $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            thread_info(
              threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
          }
        }

        guard infoResult == KERN_SUCCESS else {
          continue
        }

        let threadBasicInfo = threadInfo as thread_basic_info
        if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
          totalUsageOfCPU += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE))
        }
      }

      vm_deallocate(
        mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)),
        vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
    }

    return totalUsageOfCPU
  }
}
