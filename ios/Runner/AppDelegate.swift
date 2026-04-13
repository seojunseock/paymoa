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

    // window 배경 흰색 + 명시적으로 foreground 올리기 (타이밍 문제 방지)
    window?.backgroundColor = UIColor.white
    window?.makeKeyAndVisible()

    if let flutterVC = window?.rootViewController as? FlutterViewController {
      flutterVC.view.backgroundColor = UIColor.white

      // LaunchScreen.storyboard를 splashScreenView로 로드
      // Metal 레이어 위에 덮여서 Flutter 첫 프레임까지 표시됨
      // Flutter가 첫 프레임 렌더링 완료 시 자동 제거
      flutterVC.loadDefaultSplashScreenView()
    }

    return result
  }
}
