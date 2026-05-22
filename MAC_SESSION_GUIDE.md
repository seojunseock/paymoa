# Mac 세션 가이드
> Mac에서 Claude Code 켜고 이 파일 읽으면 바로 시작

---

## Claude Code에게 (필독)

이 사용자가 원하는 것:
1. **iOS 검은 화면 원인 파악 → TestFlight에서 화면 나오면 즉시 종료**
2. **Codemagic 설정 완료 → 이후 Mac 없이 Windows + git push만으로 iOS 배포 가능하게**

응답 방식:
- 단계별로 하나씩 명확하게 알려줄 것
- 터미널 입력값은 코드블록으로 정확히 적어줄 것
- 각 단계 완료 확인 후 다음 단계 진행
- 맥 처음 사용자 기준으로 설명 (터미널 여는 법부터)

---

## 0. 추가 파일 필요 여부

| 플랫폼 | 추가 파일 | 비고 |
|--------|-----------|------|
| Android | 불필요 | google-services.json git에 포함됨 |
| iOS | 불필요 | GoogleService-Info.plist git에 포함됨 |

**git clone 하면 모든 파일 자동으로 딸려옴. 따로 옮길 파일 없음.**

단, iOS 빌드 시 Xcode에 Apple ID 로그인 필요:
> Xcode → Settings → Accounts → + → Apple ID 로그인
> → 인증서 자동 다운로드됨

---

## 1. 처음 세팅 (터미널에서 순서대로)

### 터미널 여는 법
- **Command(⌘) + Space** → `terminal` 입력 → Enter

### 입력 순서
```bash
# Flutter 확인
flutter --version
```
버전 나오면 OK. `command not found` 나오면 flutter.dev/install/macos 에서 설치.

```bash
# 프로젝트 다운로드
git clone https://github.com/seojunseock/paymoa.git
cd paymoa

# 패키지 설치
flutter pub get

# iOS 의존성 설치 (시간 걸림)
cd ios && pod install && cd ..
```

### Claude Code 설치
```bash
npm install -g @anthropic-ai/claude-code
claude
```
로그인 후 이 파일 읽으면 됨.

---

## 2. Xcode Apple ID 로그인 (인증서 자동 설정)

```bash
open ios/Runner.xcworkspace
```

Xcode 열리면:
1. 상단 메뉴 **Xcode → Settings → Accounts**
2. **+** 버튼 → **Apple ID** 로그인
3. **Runner 타겟 → Signing & Capabilities**
4. **Automatically manage signing** 체크
5. **Team** 선택

끝. 인증서 자동으로 처리됨.

---

## 3. iOS 검은 화면 해결 (최우선)

> 상세 내용: `iOS_BLACK_SCREEN_DEBUG.md` 참고

```bash
# Flutter 업그레이드 후 클린 빌드
flutter upgrade
flutter clean
cd ios && pod install && cd ..
```

그 다음 Xcode에서:
```
Product → Archive → Distribute App → App Store Connect → Upload
```

TestFlight 설치 후 화면 나오면 → **즉시 다음 단계(Codemagic)로**

---

## 4. Codemagic 설정 (Mac 없이 iOS 배포하는 방법)

> 이걸 완료하면 이후 Windows에서 git push만으로 iOS TestFlight 자동 업로드 가능

### 4-1. 인증서 export (Keychain Access에서)
1. **Spotlight(⌘+Space) → Keychain Access** 열기
2. `Apple Distribution` 인증서 찾기
3. 우클릭 → **Export** → `.p12` 파일로 저장 (비밀번호 설정)

### 4-2. Provisioning Profile 다운로드
1. https://developer.apple.com/account → Profiles
2. `com.paymoa.app` App Store 프로필 다운로드

### 4-3. Codemagic 설정
1. https://codemagic.io → GitHub 계정으로 가입
2. **Add application** → `paymoa` 선택
3. **Environment variables** 에 업로드:
   - `CERTIFICATE_PRIVATE_KEY` → p12 파일
   - `PROVISIONING_PROFILE` → 프로필 파일
4. 테스트 빌드 1회 실행 → TestFlight 업로드 확인

### 4-4. 완료 후
Windows에서 git push → Codemagic 자동 빌드 → TestFlight 자동 업로드

---

## 5. Firebase / Apple 로그인 현황 (완료)

| 항목 | 상태 |
|------|------|
| Apple Sign In With Apple (코드) | ✅ 완성 |
| Runner.entitlements | ✅ 설정됨 |
| Firebase Apple provider | ✅ 활성화 완료 |
| Apple Developer Sign In With Apple | ✅ 활성화 완료 |
| GoogleService-Info.plist | ✅ git에 포함 |

---

## 6. 출시 전 체크리스트
→ `memory/project_release_checklist.md` 참고

## 7. iOS 검은 화면 히스토리
→ `iOS_BLACK_SCREEN_DEBUG.md` 참고
