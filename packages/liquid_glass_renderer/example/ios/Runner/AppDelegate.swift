import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // With FLTEnableWideGamut, Flutter renders into an extended-range surface,
    // but its layer does not request EDR, so iOS clips glass highlights above
    // SDR white on screen.
    NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { notification in
      guard #available(iOS 16.0, *),
        let scene = notification.object as? UIWindowScene
      else { return }
      for window in scene.windows {
        (window.rootViewController?.view.layer as? CAMetalLayer)?
          .wantsExtendedDynamicRangeContent = true
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    engineBridge.pluginRegistry.registrar(forPlugin: "NativeGlass")?
      .register(NativeGlassFactory(), withId: "native-glass")
  }
}

/// System Liquid Glass as a platform view, so the example can show Apple's
/// glass over the same Flutter content as its own (see `glint_ab_main.dart`).
final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    let style = (args as? [String: Any])?["style"] as? String
    return NativeGlassView(frame: frame, clear: style == "clear")
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class NativeGlassView: NSObject, FlutterPlatformView {
  private let glass: UIView

  init(frame: CGRect, clear: Bool) {
    if #available(iOS 26.0, *) {
      let view = UIVisualEffectView(effect: UIGlassEffect(style: clear ? .clear : .regular))
      view.cornerConfiguration = .capsule()
      glass = view
    } else {
      glass = UIView(frame: frame)
    }
    glass.frame = frame
    glass.isUserInteractionEnabled = false
  }

  func view() -> UIView { glass }
}
