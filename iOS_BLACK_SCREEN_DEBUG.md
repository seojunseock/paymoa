# iOS 검은 화면 디버깅 파일
> Mac 세션에서 이 파일 먼저 열 것.

---

## 핵심 상황 요약

| 항목 | 내용 |
|------|------|
| 증상 | TestFlight 설치 후 앱 실행 시 검은 화면 |
| 기기 | iPhone 16 Pro, iOS 26.x |
| Android | 완전 정상 |
| Flutter | 3.44.0 (업그레이드 후 해결) |
| 빌드 도구 | Mac 직접 빌드 (Xcode 16.x) |
| 크래시 여부 | 크래시 없음 — 상태바 보임, 앱 살아있음 |
| 최종 결론 | iOS 26에서 UIScene 미지원 → UIWindow가 화면에 연결 안 됨 |
| **현재 상태** | ✅ 검은 화면 해결 / ⚠️ 애플 로그인 별도 설정 필요 |

---

## 지금까지 시도한 것 (빌드 1~75) — 모두 실패

| 시도 | 결과 |
|------|------|
| Firebase 제거 | 검은 화면 지속 |
| Kakao 제거 | 검은 화면 지속 |
| 빌드 47: 초록 화면만 출력 (Hello World 수준) | 검은 화면 지속 → Dart 코드 문제 아님 확정 |
| FLTEnableImpeller = false (Impeller 비활성화) | 검은 화면 지속 |
| CADisableMinimumFrameDurationOnPhone 키 시도 | 효과 없음 |
| Codemagic M2 빌드 | 검은 화면 지속 |
| GitHub Actions 빌드 | 검은 화면 지속 |

결정적 사실: 빌드 47에서 Flutter 초록 화면 한 줄짜리 앱도 검은 화면 → Flutter 엔진이 iOS 26에서 렌더링을 못 하는 것

---

## ✅ 검은 화면 해결 (2026-05-23) — 빌드 78+

### 근본 원인

iOS 26부터 Apple이 UIScene 라이프사이클을 강제화함.
기존 Flutter 기본 구조(FlutterAppDelegate)는 UIScene을 인식하지 못해서
FlutterViewController가 연결된 UIWindow가 어떤 UIWindowScene에도 속하지 않음.
→ iOS 26이 이 Window를 화면에 표시하지 않음 → 검은 화면.

Flutter의 Dart 코드는 정상 실행 (print 로그 확인됨).
화면에만 픽셀이 안 나오는 것.

관련 GitHub 이슈: https://github.com/flutter/flutter/issues/186572

### 소거법 디버깅 과정

1. Dart print 찍어보기 → `>>> MAIN CALLED`, `>>> RUNAPP CALLED` 출력 확인 → Dart는 정상
2. MaterialApp을 빨간 Scaffold 한 줄로 단순화 → 여전히 검은화면 → Flutter 렌더링 문제
3. 시뮬레이터 실행 → 시뮬레이터에서도 검은화면 → 기기 특정 문제 아님
4. GitHub 이슈 발견 → iOS 26 + Flutter UIScene 미지원 버그 확인
5. SceneDelegate에 `print("window: \(self.window)")` → `window: nil` 출력 → Window가 없음 확인
6. SceneDelegate에서 UIWindow 수동 생성 → **빨간 화면 출력 성공!**
7. 원래 main.dart 복구 → 로그인 화면 정상 표시 ✅

### 변경된 파일 3개

---

#### 1. `ios/Runner/SceneDelegate.swift` — 신규 생성

**기존:** 없었음 (Flutter 기본 구조는 AppDelegate만 사용)

**변경 후:**
```swift
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let engine = FlutterEngine(name: "main", project: nil)
        engine.run()
        GeneratedPluginRegistrant.register(with: engine)

        let flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let newWindow = UIWindow(windowScene: windowScene)
        newWindow.rootViewController = flutterVC
        newWindow.makeKeyAndVisible()
        self.window = newWindow

        print(">>> SCENE: window created OK")
    }
}
```

**이 파일이 하는 일:**
- iOS 26이 앱을 시작할 때 Scene(화면 영역)을 생성한다
- 우리가 이 타이밍을 잡아서 FlutterEngine(Dart VM)을 직접 실행
- `GeneratedPluginRegistrant.register(with: engine)` → Firebase, Kakao, Google 등 모든 플러그인을 이 엔진에 연결
- FlutterViewController를 UIWindow에 넣고, 그 UIWindow를 UIWindowScene에 연결
- `makeKeyAndVisible()` → iOS에게 "이 창이 메인 창이야, 화면에 보여줘" 선언

**Xcode에 추가하는 방법:**
1. Finder에서 SceneDelegate.swift 파일 생성
2. Xcode → Runner 폴더 우클릭 → "Add Files to Runner"
3. SceneDelegate.swift 선택 → Add 클릭

---

#### 2. `ios/Runner/AppDelegate.swift` — 수정

**기존 (Flutter 기본):**
```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

**변경 후:**
```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return true
  }
}
```

**왜 바꿨나:**
- 기존 코드는 `super.application(...)` 호출 → FlutterAppDelegate가 UIWindow를 생성하지만 UIWindowScene에 연결 안 됨
- SceneDelegate가 UIWindow를 담당하므로 AppDelegate는 `true`만 반환
- `GeneratedPluginRegistrant.register(with: self)` 제거 → 대신 SceneDelegate에서 엔진에 직접 등록

**남은 경고 (무시해도 됨):**
```
Plugin FLTFirebaseAuthPlugin uses deprecated application lifecycle events.
Plugin FLTGoogleSignInPlugin uses deprecated application lifecycle events.
```
이 경고는 각 플러그인이 아직 UIScene 라이프사이클을 완전히 지원 안 해서 나오는 것.
앱은 정상 동작하며, 각 플러그인이 업데이트되면 자연히 사라짐.

---

#### 3. `ios/Runner/Info.plist` — UIApplicationSceneManifest 추가

**기존:** UIApplicationSceneManifest 키 없음

**추가된 내용:**
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>UIWindowScene</string>
                <key>UISceneDelegateClassName</key>
                <string>Runner.SceneDelegate</string>
                <key>UISceneConfigurationName</key>
                <string>flutter</string>
            </dict>
        </array>
    </dict>
</dict>
```

**이 설정이 하는 일:**
- iOS에게 "이 앱은 SceneDelegate를 사용한다" 선언
- `UISceneDelegateClassName: Runner.SceneDelegate` → iOS가 SceneDelegate.swift를 찾아서 실행

---

### 결과

| 항목 | 전 | 후 |
|------|----|----|
| 검은 화면 | 발생 (빌드 1~75) | ✅ 해결 |
| 로그인 화면 | 안 뜸 | ✅ 정상 표시 |
| 카카오 로그인 | 확인 불가 | ✅ 정상 |
| 구글 로그인 | 확인 불가 | ✅ 정상 |
| 애플 로그인 | 확인 불가 | ✅ 정상 |

---

## ✅ 애플 로그인 해결 (2026-05-23)

### 증상
Face ID까지 통과하지만 로그인 실패.
에러: `[firebase_auth/invalid-credential] Invalid OAuth response from apple.com`

### 원인
`firebase_auth` v6.x에서 Apple Sign In 시 `authorizationCode`를 같이 전달해야
Firebase 백엔드가 Apple 토큰을 검증할 수 있음.
기존 코드는 `identityToken`만 전달 → Firebase가 Apple OAuth 응답을 처리 못해 거부.

### 변경된 코드 (`lib/auth/auth_service.dart`)

**기존:**
```dart
final oauthCredential = OAuthProvider('apple.com').credential(
  idToken: appleCredential.identityToken,
  rawNonce: rawNonce,
);
```

**변경 후:**
```dart
final oauthCredential = OAuthProvider('apple.com').credential(
  idToken: appleCredential.identityToken,
  rawNonce: rawNonce,
  accessToken: appleCredential.authorizationCode,  // 추가
);
```

### 추가 설정 (Apple Developer Portal)
- `com.paymoa.app` → Sign In with Apple → Enable as primary App ID → Save

### Firebase Console 설정
- Authentication → Apple → 사용 설정됨
- Service ID / Team ID / Key ID / 비공개 키: **모두 비워둠** (iOS 네이티브는 불필요)

---

## 비용 현황 (CI/CD)

| 서비스 | 상태 |
|--------|------|
| Codemagic 무료 500분 | 소진 + $10 추가 사용 |
| GitHub Actions | 이번 달 소진 (매달 리셋) |
| Mac 직접 빌드 | 무료 |

---

## TestFlight 업로드 절차

검은 화면 고쳐진 빌드 (빌드 78+) TestFlight 올리기:

```bash
cd /Users/jeonsinhwi/paymoa
flutter clean
cd ios && pod install && cd ..
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

Xcode에서:
1. Product → Archive
2. Distribute App → App Store Connect → Upload
3. TestFlight 처리 대기 (10~30분)
4. TestFlight에서 설치 → 로그인 화면 확인

---

## 해결 기록

### 빌드 79 (2026-05-23) — TestFlight 업로드 대상

| 항목 | 내용 |
|------|------|
| 빌드 번호 | 79 (`pubspec.yaml`: `1.0.6+79`) |
| Flutter 버전 | 3.44.0 |
| 해결된 문제 1 | iOS 26 검은 화면 |
| 해결된 문제 2 | 애플 로그인 오류 |
| 해결된 문제 3 | 애플 로그인 버튼 아이콘 정렬 |

---

#### 문제 1: iOS 26 검은 화면
- 원인: iOS 26 UIScene 미지원 → UIWindow가 화면에 미연결
- 해결: SceneDelegate.swift 신규 생성 + Info.plist UIApplicationSceneManifest 추가

#### 문제 2: 애플 로그인 `[firebase_auth/invalid-credential]`
- 원인: `firebase_auth` v6에서 `authorizationCode`를 같이 전달해야 Firebase가 검증 가능
- 해결: `lib/auth/auth_service.dart` — `OAuthProvider.credential()`에 `accessToken: appleCredential.authorizationCode` 추가
- 추가 설정: Apple Developer Portal → `com.paymoa.app` → Sign In with Apple → Enable as primary App ID
- Firebase Console: Authentication → Apple → 사용 설정 (Service ID/Team ID/Key ID/비공개 키 모두 비워둠)

#### 문제 3: 애플 로그인 버튼 아이콘 정렬
- 원인: `SignInWithAppleButton` 기본값이 아이콘+텍스트 가운데 정렬 → 카카오/구글과 다른 위치
- 해결: `lib/auth/login_screen.dart` — `iconAlignment: SignInWithAppleButtonIconAlignment.left` 추가
- Apple 가이드라인 준수 (공식 패키지에서 제공하는 옵션)

---

#### 로그인 최종 상태
| 로그인 | 상태 |
|--------|------|
| 카카오 | ✅ 정상 |
| 구글 | ✅ 정상 |
| 애플 | ✅ 정상 |
