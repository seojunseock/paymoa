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

    // Flutter 첫 프레임 렌더링 전 검은 화면 방지
    // window 배경 + FlutterViewController 배경 모두 흰색으로 설정
    window?.backgroundColor = UIColor.white
    if let flutterVC = window?.rootViewController as? FlutterViewController {
      flutterVC.view.backgroundColor = UIColor.white
    }

    return result
  }
}
