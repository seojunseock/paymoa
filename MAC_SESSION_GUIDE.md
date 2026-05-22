# Mac 세션 가이드 (4시간)
> 이 파일을 Mac에서 Claude Code로 열어서 바로 체크리스트로 활용

---

## 0. 프로젝트 이전 방법 (Windows → Mac)

### 방법: Git 클론 (가장 빠름)
Mac에서 터미널 열고 순서대로 실행:

```bash
# 1. Flutter 설치 확인 (없으면 아래 링크에서 설치)
flutter --version
# https://docs.flutter.dev/get-started/install/macos

# 2. Xcode 설치 확인 (App Store에서 사전 설치 권장)
xcode-select --version
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# 3. CocoaPods 설치 확인
pod --version
# 없으면: sudo gem install cocoapods

# 4. 프로젝트 클론
git clone https://github.com/[your-repo]/paycount.git
cd paycount

# 5. 패키지 설치
flutter pub get

# 6. iOS 의존성 설치
cd ios && pod install && cd ..

# 7. 빌드 확인
flutter build ios --release
```

### Windows에서 미리 할 것 (지금)
- [ ] 현재 작업 내용 git push 완료 확인
- [ ] `git status` 확인해서 uncommitted 파일 없는지 체크

---

## 1. Apple Developer Console 확인 (필수 - Mac에서)

URL: https://developer.apple.com/account

### 1-1. App ID 설정
- [x] **Identifiers** → `com.paymoa.app` → **Sign In with Apple** → ✅ 활성화 완료
- [ ] **Push Notifications** → 필요 시 Enabled

### 1-2. Certificates (인증서)
- [ ] **Certificates** → iOS Distribution 인증서 유효 여부 확인 (만료일 체크)
- [ ] Mac 키체인에 인증서가 있는지 확인 (없으면 새로 생성 또는 p12 파일로 가져오기)

### 1-3. Provisioning Profiles
- [ ] **Profiles** → `com.paymoa.app` App Store Distribution 프로필 있는지 확인
- [ ] 없으면: + 버튼 → App Store → com.paymoa.app 선택 → 인증서 연결 → 다운로드

---

## 2. Firebase Console 확인

URL: https://console.firebase.google.com → paycount 프로젝트

### 2-1. Apple 로그인 설정
- [x] **Authentication** → **Sign-in method** → **Apple** → ✅ 활성화 완료

### 2-2. iOS 앱 설정
- [ ] **Project Settings** → iOS 앱 → Bundle ID: `com.paymoa.app` 확인
- [ ] `GoogleService-Info.plist`가 `ios/Runner/` 안에 있는지 확인 (git에는 없을 수 있음)
  - 없으면: Firebase Console에서 다운로드 → `ios/Runner/` 에 넣기

---

## 3. Xcode에서 Apple Sign In Capability 확인

```bash
open ios/Runner.xcworkspace  # 반드시 .xcworkspace로 열기 (xcodeproj 아님)
```

Xcode 열리면:
- [ ] **Runner** 타겟 → **Signing & Capabilities** 탭
- [ ] **Sign In with Apple** capability가 목록에 있는지 확인
  - 없으면: + Capability → Sign In with Apple 추가
- [ ] **Automatically manage signing** 체크 → Team 선택
- [ ] Bundle ID: `com.paymoa.app` 확인

---

## 4. iOS 검은 화면 이슈 (빌드 47까지 미해결)

### 현재까지 시도한 것
- Impeller 비활성화 (`FLTEnableImpeller = false`) → 효과 없음
- Flutter 렌더링 자체 불가 (Dart 코드 실행 전 문제)
- iPhone 16 Pro, iOS 18.x, TestFlight에서만 발생

### Mac에서 시도할 것 (순서대로)
```bash
# 1. Flutter 버전 업그레이드 시도
flutter upgrade
flutter --version  # 버전 기록해두기

# 2. iOS 클린 빌드
flutter clean
cd ios && pod install && cd ..
flutter build ios --release

# 3. Xcode에서 직접 Archive
# Product → Archive → Distribute App → App Store Connect
```

### Xcode 콘솔 로그 확인 (핵심)
- iPhone 연결 → Xcode → **Window** → **Devices and Simulators**
- 기기 선택 → **Open Console** → 앱 실행하면서 에러 메시지 확인
- "dyld", "crash", "signal" 키워드 찾기

### 체크포인트
- [ ] Xcode 빌드 로그에서 warning/error 확인
- [ ] Archive 후 TestFlight 업로드
- [ ] 검은 화면 재현 여부 확인

---

## 5. TestFlight 업로드 (정상 빌드 후)

```
Xcode → Product → Archive
→ Distribute App
→ App Store Connect
→ Upload
```

또는 Transporter 앱 사용 (Mac App Store에서 무료)

---

## 6. 로그인 코드 현황 (이미 완성 - 확인용)

| 항목 | 상태 |
|------|------|
| sign_in_with_apple 패키지 | ✅ ^6.1.0 |
| Runner.entitlements (Apple capability) | ✅ 설정됨 |
| Xcode project.pbxproj entitlements 연결 | ✅ Debug/Release/Profile 모두 |
| auth_service.dart signInWithApple() | ✅ nonce + SHA256 + Firebase OAuth |
| login_screen.dart Apple 버튼 | ✅ iOS에서만 표시, 탭 핸들러 연결 |
| Firebase Auth Apple provider | ✅ 활성화 완료 (2025-05-22) |

**코드는 완성. Firebase Console + Apple Developer 콘솔 설정만 확인하면 됨.**

---

## 7. Windows에서 iOS 배포하는 방법 (장기 목표)

### 현재 문제
Windows에서는 Xcode가 없어서 iOS .ipa 빌드 불가능.
`flutter build ios`는 Mac 전용.

### 해결책: Codemagic CI/CD

**개념**: git push → Codemagic(클라우드 Mac) → iOS 빌드 → TestFlight 자동 업로드

#### 설정 방법
1. https://codemagic.io 가입 (GitHub 계정 연동)
2. 프로젝트 연결 → Flutter 선택
3. **Mac에서 미리 준비할 것**:
   - Apple Distribution 인증서 → p12 파일로 export
   - Provisioning Profile 다운로드
   - Codemagic에 업로드
4. `codemagic.yaml` 파일 프로젝트에 추가

#### codemagic.yaml 기본 구조
```yaml
workflows:
  ios-release:
    name: iOS Release
    max_build_duration: 60
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    scripts:
      - flutter pub get
      - cd ios && pod install
      - flutter build ios --release
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
```

#### 무료 플랜
- 월 500분 무료 (iOS 빌드 약 6~8회)
- 유료: $95/월 (무제한)

#### Mac에서 할 것
- [ ] Codemagic 가입 + 프로젝트 연결
- [ ] p12 인증서 export (Keychain Access → 인증서 우클릭 → Export)
- [ ] Codemagic에 인증서 + 프로필 업로드
- [ ] 테스트 빌드 1회 실행

---

## 8. 출시 전 체크리스트 링크
→ `memory/project_release_checklist.md` 참고

## 9. iOS 검은 화면 이슈 히스토리
→ `memory/project_ios_black_screen.md` 참고
