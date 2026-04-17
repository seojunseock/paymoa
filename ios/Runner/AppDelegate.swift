import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // iOS 18 검은 화면 방지: Flutter 첫 프레임 렌더링 전 window 배경색 지정
    window?.backgroundColor = UIColor.white
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
