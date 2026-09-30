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
  }
}
