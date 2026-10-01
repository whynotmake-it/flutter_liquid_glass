import Cocoa
import FlutterMacOS
import Metal
import QuartzCore
import os.signpost

/// Measures the process's GPU execution time by interposing command-buffer
/// creation on the concrete `MTLCommandQueue` class and reading each
/// completed buffer's `gpuStartTime`/`gpuEndTime` — full-precision doubles
/// straight from Metal, with no external tracer. This covers every command
/// buffer the process submits (Impeller rendering, Flutter GPU geometry,
/// backdrop filters) for the whole measure window. GPU busy is the union of
/// completed-buffer execution intervals, so concurrently executing buffers
/// are not double-counted; idle gaps inside one buffer's span still count as
/// busy, a slight overcount that is stable across runs.
private final class GpuCommandBufferTimer {
  static let shared = GpuCommandBufferTimer()
  private static var observedBufferKey: UInt8 = 0

  private let lock = NSLock()
  private var installationResult: Bool?
  private var installationFailureReason: String?
  private var sessionActive = false
  private var sessionStart: CFTimeInterval = 0
  private var intervals: [(start: Double, end: Double)] = []
  private var bufferCount = 0

  /// Begins a measurement session, interposing Metal on first use. Returns
  /// `available: false` with a reason instead of throwing so a non-Metal
  /// context degrades to "unavailable" rather than failing the benchmark.
  func begin() -> [String: Any] {
    install()
    lock.lock()
    defer { lock.unlock() }
    guard installationResult == true else {
      return [
        "available": false,
        "reason": installationFailureReason ?? "not installed",
      ]
    }
    sessionActive = true
    sessionStart = CACurrentMediaTime()
    intervals.removeAll(keepingCapacity: true)
    bufferCount = 0
    return ["available": true]
  }

  /// Ends the session and returns the unioned GPU busy time. Buffers still
  /// executing when the session ends are dropped and pre-session buffers are
  /// clipped to the session start; both effects are at most one frame of
  /// boundary fuzz on a multi-second window.
  func end() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    guard installationResult == true, sessionActive else {
      return [
        "available": false,
        "reason": installationFailureReason ?? "no active measurement session",
      ]
    }
    sessionActive = false
    let sessionEnd = CACurrentMediaTime()
    let merged = mergedIntervals(clippedTo: sessionEnd)
    let busySeconds = merged.reduce(0) { $0 + ($1.end - $1.start) }
    let windowSeconds = sessionEnd - sessionStart
    let buckets = bucketedBusyMilliseconds(
      merged,
      windowSeconds: windowSeconds
    )
    let observedBuffers = bufferCount
    intervals.removeAll(keepingCapacity: true)
    bufferCount = 0
    return [
      "available": true,
      "busyMilliseconds": busySeconds * 1000,
      "windowMilliseconds": windowSeconds * 1000,
      "bufferCount": observedBuffers,
      "bucketMilliseconds": Int(Self.bucketSeconds * 1000),
      "bucketBusyMilliseconds": buckets,
    ]
  }

  private static let bucketSeconds = 0.1

  private func mergedIntervals(
    clippedTo sessionEnd: CFTimeInterval
  ) -> [(start: Double, end: Double)] {
    let clipped = intervals
      .compactMap { interval -> (start: Double, end: Double)? in
        let start = max(interval.start, sessionStart)
        let end = min(interval.end, sessionEnd)
        return end > start ? (start: start, end: end) : nil
      }
      .sorted { $0.start < $1.start }
    var merged: [(start: Double, end: Double)] = []
    for interval in clipped {
      if let last = merged.last, interval.start <= last.end {
        merged[merged.count - 1].end = max(last.end, interval.end)
      } else {
        merged.append(interval)
      }
    }
    return merged
  }

  /// Splits the merged busy union into fixed 100 ms buckets relative to the
  /// session start so the parser can see phase spread inside one window.
  private func bucketedBusyMilliseconds(
    _ merged: [(start: Double, end: Double)],
    windowSeconds: Double
  ) -> [Double] {
    let bucketCount = max(1, Int(ceil(windowSeconds / Self.bucketSeconds)))
    var buckets = [Double](repeating: 0, count: bucketCount)
    for interval in merged {
      var index = max(
        0,
        min(
          Int((interval.start - sessionStart) / Self.bucketSeconds),
          bucketCount - 1
        )
      )
      var cursor = interval.start
      while cursor < interval.end {
        let bucketEnd = sessionStart + Double(index + 1) * Self.bucketSeconds
        let sliceEnd = min(interval.end, bucketEnd)
        buckets[index] += (sliceEnd - cursor) * 1000
        if sliceEnd >= interval.end { break }
        cursor = sliceEnd
        index = min(index + 1, bucketCount - 1)
      }
    }
    return buckets
  }

  /// Interposes command-buffer creation once per process. Metal returns one
  /// private concrete queue class per device, so patching the class of a
  /// probe queue also covers the queues Impeller and Flutter GPU already
  /// created: Objective-C dispatches through the class at call time.
  private func install() {
    lock.lock()
    defer { lock.unlock() }
    guard installationResult == nil else { return }
    guard let device = MTLCreateSystemDefaultDevice(),
          let probeQueue = device.makeCommandQueue(),
          let queueClass = object_getClass(probeQueue)
    else {
      installationResult = false
      installationFailureReason = "no Metal device or command queue"
      return
    }
    var interposed = 0
    for selectorName in ["commandBuffer", "commandBufferWithUnretainedReferences"]
    where interposeFactory(on: queueClass, selectorName: selectorName) {
      interposed += 1
    }
    if interposeDescriptorFactory(
      on: queueClass,
      selectorName: "commandBufferWithDescriptor:"
    ) {
      interposed += 1
    }
    if interposed == 0 {
      installationResult = false
      installationFailureReason =
        "could not interpose any command-buffer factory on \(queueClass)"
    } else {
      installationResult = true
    }
  }

  private func interposeFactory(
    on queueClass: AnyClass,
    selectorName: String
  ) -> Bool {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(queueClass, selector) else {
      return false
    }
    typealias Factory = @convention(c) (AnyObject, Selector) -> AnyObject?
    let original = unsafeBitCast(
      method_getImplementation(method),
      to: Factory.self
    )
    let replacement: @convention(block) (AnyObject) -> AnyObject? = { queue in
      let result = original(queue, selector)
      if let buffer = result as? MTLCommandBuffer {
        GpuCommandBufferTimer.shared.observe(buffer)
      }
      return result
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
    return true
  }

  private func interposeDescriptorFactory(
    on queueClass: AnyClass,
    selectorName: String
  ) -> Bool {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(queueClass, selector) else {
      return false
    }
    typealias Factory =
      @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
    let original = unsafeBitCast(
      method_getImplementation(method),
      to: Factory.self
    )
    let replacement: @convention(block) (AnyObject, AnyObject?) -> AnyObject? =
      { queue, descriptor in
        let result = original(queue, selector, descriptor)
        if let buffer = result as? MTLCommandBuffer {
          GpuCommandBufferTimer.shared.observe(buffer)
        }
        return result
      }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
    return true
  }

  private func observe(_ buffer: MTLCommandBuffer) {
    // A factory variant could delegate to another interposed variant for the
    // same buffer; the marker guarantees one completion handler per buffer.
    if objc_getAssociatedObject(buffer, &Self.observedBufferKey) != nil {
      return
    }
    objc_setAssociatedObject(
      buffer,
      &Self.observedBufferKey,
      true,
      .OBJC_ASSOCIATION_RETAIN
    )
    buffer.addCompletedHandler { completed in
      GpuCommandBufferTimer.shared.recordCompletion(of: completed)
    }
  }

  private func recordCompletion(of buffer: MTLCommandBuffer) {
    let start = buffer.gpuStartTime
    let end = buffer.gpuEndTime
    // Buffers that errored or never reached the GPU report zero timestamps.
    guard start > 0, end > start else { return }
    lock.lock()
    defer { lock.unlock() }
    guard sessionActive else { return }
    bufferCount += 1
    intervals.append((start: start, end: end))
  }
}

private final class BenchmarkMetrics {
  private let log = OSLog(
    subsystem: "com.example.liquidGlassRenderer",
    category: "PointsOfInterest"
  )
  private var intervals: [String: OSSignpostID] = [:]
  private let samplingQueue = DispatchQueue(
    label: "com.example.liquidGlassRenderer.memorySampling",
    qos: .utility
  )
  private var samplingTimer: DispatchSourceTimer?
  private var memorySamples: [[String: Any]] = []

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configuration":
      let environment = ProcessInfo.processInfo.environment
      let scenario = environment["LIQUID_GLASS_BENCHMARK_SCENARIO"] ?? "staticSingle"
      let warmupSeconds = Int(environment["LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS"] ?? "3") ?? 3
      let measureSeconds = Int(environment["LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS"] ?? "8") ?? 8
      let traceMeasureMilliseconds = Int(
        environment["LIQUID_GLASS_BENCHMARK_TRACE_MEASURE_MILLISECONDS"] ?? "500"
      ) ?? 500
      let repetition = Int(environment["LIQUID_GLASS_BENCHMARK_REPETITION"] ?? "1") ?? 1
      let traceGraceSeconds = Int(environment["LIQUID_GLASS_BENCHMARK_TRACE_GRACE_SECONDS"] ?? "40") ?? 40
      let traceRun = environment["LIQUID_GLASS_BENCHMARK_TRACE_RUN"] == "1"
      let traceStartGate = environment["LIQUID_GLASS_BENCHMARK_TRACE_START_GATE"] ?? ""
      let configuration: [String: Any] = [
        "scenario": scenario,
        "warmupSeconds": warmupSeconds,
        "measureSeconds": measureSeconds,
        "traceMeasureMilliseconds": traceMeasureMilliseconds,
        "repetition": repetition,
        "traceGraceSeconds": traceGraceSeconds,
        "traceRun": traceRun,
        "traceStartGate": traceStartGate,
      ]
      result(configuration)
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
    case "startGpuTiming":
      result(GpuCommandBufferTimer.shared.begin())
    case "stopGpuTiming":
      result(GpuCommandBufferTimer.shared.end())
    case "sampleMemory":
      result(memorySnapshot())
    case "startMemorySampling":
      startMemorySampling()
      result(nil)
    case "stopMemorySampling":
      result(stopMemorySampling())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startMemorySampling() {
    samplingQueue.sync {
      samplingTimer?.cancel()
      memorySamples = [memorySnapshot()]
      let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
      timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
      timer.setEventHandler { [weak self] in
        guard let self else { return }
        self.memorySamples.append(self.memorySnapshot())
      }
      samplingTimer = timer
      timer.resume()
    }
  }

  private func stopMemorySampling() -> [[String: Any]] {
    samplingQueue.sync {
      samplingTimer?.cancel()
      samplingTimer = nil
      let samples = memorySamples
      memorySamples = []
      return samples
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
