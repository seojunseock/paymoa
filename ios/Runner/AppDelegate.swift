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

    // 진단용: 앱이 살아있는지 네이티브 알림창 표시 (1초 후)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      let alert = UIAlertController(
        title: "진단: 앱 실행 중",
        message: "iOS 네이티브 정상. Flutter 렌더링 상태 확인 필요.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "확인", style: .default))
      self.window?.rootViewController?.present(alert, animated: true)
    }

    return result
  }
}
