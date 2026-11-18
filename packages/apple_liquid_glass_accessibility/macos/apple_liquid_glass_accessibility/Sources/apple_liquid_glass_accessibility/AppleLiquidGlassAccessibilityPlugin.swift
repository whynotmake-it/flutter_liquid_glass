import Accessibility
import AppKit
import FlutterMacOS

public class AppleLiquidGlassAccessibilityPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "apple_liquid_glass_accessibility",
      binaryMessenger: registrar.messenger)
    channel.setStreamHandler(AppleLiquidGlassAccessibilityPlugin())
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    // AppKit posts display option changes to the workspace's own center.
    var sources = [
      (
        NSWorkspace.shared.notificationCenter,
        NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
      )
    ]
    if #available(macOS 26.1, *) {
      sources.append(
        (
          NotificationCenter.default,
          AccessibilitySettings.showBordersEnabledStatusDidChangeNotification
        ))
    }
    observers = sources.map { center, name in
      (
        center,
        center.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in self?.report()
        }
      )
    }
    report()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    for (center, observer) in observers {
      center.removeObserver(observer)
    }
    observers = []
    sink = nil
    return nil
  }

  private func report() {
    var showBorders = false
    if #available(macOS 26.1, *) {
      showBorders = AccessibilitySettings.showBordersEnabled
    }
    sink?([
      "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
      "showBorders": showBorders,
      "prefersCrossFade": NSNull(),
      "prefersReducedResourceUsage": NSNull(),
    ])
  }
}
