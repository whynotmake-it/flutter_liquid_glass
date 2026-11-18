import Accessibility
import Flutter
import UIKit

public class AppleLiquidGlassAccessibilityPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  // The Liquid Glass slider of iOS 27 (Settings, Appearance): UIKit exports
  // its getter and change notification without declaring them, so they are
  // looked up at run time and missing before iOS 27 or once UIKit drops
  // them. The getter's argument reads the system's value when nil.
  private typealias GlassTintAmount = @convention(c) (AnyObject?) -> Float

  private static let glassTintAmount: GlassTintAmount? = dlsym(
    UnsafeMutableRawPointer(bitPattern: -2), "UIViewGlassGetTintAmount"
  ).map { unsafeBitCast($0, to: GlassTintAmount.self) }

  private static let glassTintAmountDidChange: Notification.Name? = dlsym(
    UnsafeMutableRawPointer(bitPattern: -2), "UIViewGlassTintAmountDidChangeNotification"
  ).map { Notification.Name($0.load(as: NSString.self) as String) }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "apple_liquid_glass_accessibility",
      binaryMessenger: registrar.messenger())
    channel.setStreamHandler(AppleLiquidGlassAccessibilityPlugin())
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    var names = [
      UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      UIAccessibility.prefersCrossFadeTransitionsStatusDidChange,
    ]
    if #available(iOS 26.1, *) {
      names.append(AccessibilitySettings.showBordersEnabledStatusDidChangeNotification)
    } else {
      names.append(UIAccessibility.buttonShapesEnabledStatusDidChangeNotification)
    }
    if let name = Self.glassTintAmountDidChange {
      names.append(name)
    }
    if #available(iOS 27.0, *) {
      names.append(UIApplication.systemPrefersReducedResourceUsageDidChangeNotification)
    }
    observers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in self?.report()
      }
    }
    report()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    sink = nil
    return nil
  }

  private func report() {
    let showBorders: Bool
    if #available(iOS 26.1, *) {
      showBorders = AccessibilitySettings.showBordersEnabled
    } else {
      showBorders = UIAccessibility.buttonShapesEnabled
    }
    var prefersReducedResourceUsage: Any = NSNull()
    if #available(iOS 27.0, *) {
      prefersReducedResourceUsage = UIApplication.shared.systemPrefersReducedResourceUsage
    }
    sink?([
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
      "showBorders": showBorders,
      "prefersCrossFade": UIAccessibility.prefersCrossFadeTransitions,
      "glassTintAmount": Self.glassTintAmount.map { Double($0(nil)) } as Any,
      "prefersReducedResourceUsage": prefersReducedResourceUsage,
    ])
  }
}
