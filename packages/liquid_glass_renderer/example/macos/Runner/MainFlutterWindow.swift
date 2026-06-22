import Cocoa
import FlutterMacOS
import os.signpost

private final class BenchmarkMetrics {
  private let log = OSLog(subsystem: "com.example.liquidGlassRenderer", category: "benchmark")
  private var intervals: [String: OSSignpostID] = [:]

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginInterval":
      guard let name = call.arguments as? String else {
        result(FlutterError(code: "bad_arguments", message: "Expected interval name", details: nil))
        return
      }
      let id = OSSignpostID(log: log)
      intervals[name] = id
      os_signpost(.begin, log: log, name: "LiquidGlassBenchmark", signpostID: id, "%{public}s", name)
      result(nil)
    case "endInterval":
      guard let name = call.arguments as? String, let id = intervals.removeValue(forKey: name) else {
        result(FlutterError(code: "missing_interval", message: "No matching interval", details: nil))
        return
      }
      os_signpost(.end, log: log, name: "LiquidGlassBenchmark", signpostID: id, "%{public}s", name)
      result(nil)
    case "sampleMemory":
      result(memorySnapshot())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func memorySnapshot() -> [String: Any] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }

    guard status == KERN_SUCCESS else {
      return ["error": "task_info failed: \(status)"]
    }

    return [
      "timestampMicros": Int(Date().timeIntervalSince1970 * 1_000_000),
      "physicalFootprintBytes": UInt64(info.phys_footprint),
      "residentBytes": UInt64(info.resident_size),
      "residentPeakBytes": UInt64(info.resident_size_peak),
      "internalBytes": UInt64(info.internal),
      "compressedBytes": UInt64(info.compressed),
      "virtualBytes": UInt64(info.virtual_size),
    ]
  }
}

class MainFlutterWindow: NSWindow {
  private let benchmarkMetrics = BenchmarkMetrics()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let benchmarkChannel = FlutterMethodChannel(
      name: "dev.liquid_glass_renderer/benchmark",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    benchmarkChannel.setMethodCallHandler { [weak self] call, result in
      self?.benchmarkMetrics.handle(call, result: result)
    }

    super.awakeFromNib()
  }
}
