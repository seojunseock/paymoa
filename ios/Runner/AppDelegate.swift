import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // window 배경 흰색 (기본 방어)
    window?.backgroundColor = UIColor.white

    if let flutterVC = window?.rootViewController as? FlutterViewController {
      flutterVC.view.backgroundColor = UIColor.white

      // Metal(GPU) 렌더링 레이어는 backgroundColor로 제어 불가.
      // splashScreenView = Metal 레이어 위에 덮이는 흰색 뷰.
      // Flutter가 첫 프레임을 그리면 자동으로 제거됨.
      let splash = UIView(frame: flutterVC.view.bounds)
      splash.backgroundColor = UIColor.white
      splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      flutterVC.splashScreenView = splash
    }

    return result
  }
}
