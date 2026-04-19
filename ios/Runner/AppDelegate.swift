import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // super.application() 이후에 window가 생성됨
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // iOS 18 검은 화면 방지: window 생성 후 배경색 지정
    window?.backgroundColor = UIColor.white
    window?.rootViewController?.view.backgroundColor = UIColor.white
    return result
  }
}
