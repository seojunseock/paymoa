# Mac 세션 가이드
> 열자마자 "이 파일 읽고 브리핑해줘" 라고 하면 Claude Code가 현재 상황 정리해줌

---

## Claude Code에게 — 브리핑 지침

이 파일을 읽으면 사용자에게 아래 형식으로 브리핑할 것:

1. 현재 상황 한 줄 요약
2. 오늘 해야 할 것 우선순위 순서로 번호 리스트
3. 지금 바로 시작할 첫 번째 단계 터미널 명령어

사용자 특징:
- 맥 처음 사용 (터미널 여는 법부터 설명 필요)
- 터미널 명령어는 코드블록으로 정확히 제시
- 단계마다 완료 확인 후 다음 단계 진행
- Claude Code는 파일 수정/터미널 명령어 실행 가능, Xcode GUI 조작은 불가

오늘 목표 (우선순위):
1. iOS 검은 화면 원인 파악 → TestFlight 화면 확인
2. 화면 나오면 → Codemagic 설정 (Windows에서 git push만으로 iOS 배포)
3. 화면 안 나오면 → Xcode 콘솔 로그 분석

---

## 파일 이전 관련

git clone 하면 모든 파일 자동으로 딸려옴. 따로 옮길 파일 없음.

| 플랫폼 | 추가 파일 필요 여부 |
|--------|-------------------|
| Android | 없음 (google-services.json git 포함) |
| iOS | 없음 (GoogleService-Info.plist git 포함) |

Xcode 빌드 시 Apple ID 로그인만 필요 (인증서 자동 처리).

---

## 맥 앞에 앉으면 — 순서대로

### STEP 1. 터미널 열기
**Command(⌘) + Space** 동시에 누르기  
→ `terminal` 입력  
→ Enter  
검은 창 뜨면 성공

---

### STEP 2. Flutter 확인
```
flutter --version
```
- 버전 숫자 나오면 → STEP 3으로
- `command not found` 나오면 → Claude Code한테 말하기

---

### STEP 3. 프로젝트 다운로드
```
git clone https://github.com/seojunseock/paymoa.git
```
완료되면:
```
cd paymoa
```

---

### STEP 4. 패키지 설치
```
flutter pub get
```
완료되면:
```
cd ios && pod install && cd ..
```
시간 걸림. 완료될 때까지 기다리기.

---

### STEP 5. Claude Code 설치 및 실행
```
npm install -g @anthropic-ai/claude-code
```
완료되면:
```
claude
```
로그인 후 켜지면:
> **"MAC_SESSION_GUIDE.md 읽고 브리핑해줘"**

---

### STEP 6. Xcode 열기 + Apple ID 로그인
새 터미널 탭 열기: **Command + T**
```
open ios/Runner.xcworkspace
```
Xcode 열리면:
1. 상단 메뉴 **Xcode → Settings → Accounts**
2. **+** 버튼 → Apple ID 로그인
3. **Runner 타겟 클릭 → Signing & Capabilities 탭**
4. **Automatically manage signing** 체크 → **Team** 선택

---

### STEP 7. Flutter 업그레이드 + 클린 빌드
```
flutter upgrade
flutter clean
cd ios && pod install && cd ..
```

---

### STEP 8. Xcode Archive → TestFlight 업로드
Xcode에서:
1. 상단 메뉴 **Product → Archive**
2. 완료되면 창 뜸 → **Distribute App**
3. **App Store Connect** → **Upload**
4. TestFlight 앱에서 설치 → 화면 확인

---

### STEP 9. 결과
- **화면 나오면** → Claude Code한테 "화면 나왔어" → Codemagic 설정 시작
- **화면 안 나오면** → Xcode 상단 **Window → Devices and Simulators** → 기기 선택 → **Open Console** → 로그 복사해서 Claude Code에 붙여넣기

---

## Codemagic 설정 (화면 나온 후 진행)

> Windows에서 git push만으로 iOS TestFlight 자동 업로드 가능해짐

### 인증서 export
1. **Spotlight(⌘+Space) → Keychain Access** 열기
2. `Apple Distribution` 인증서 찾기
3. 우클릭 → **Export** → `.p12` 파일 저장 (비밀번호 설정)

### Provisioning Profile 다운로드
1. https://developer.apple.com/account → Profiles
2. `com.paymoa.app` App Store 프로필 다운로드

### Codemagic 가입 + 연결
1. https://codemagic.io → GitHub 계정 가입
2. **Add application** → `paymoa` 선택
3. 인증서(.p12) + 프로필 업로드
4. 테스트 빌드 실행 → TestFlight 자동 업로드 확인

---

## Firebase / Apple 로그인 현황 (완료)

| 항목 | 상태 |
|------|------|
| Apple Sign In With Apple 코드 | ✅ 완성 |
| Runner.entitlements | ✅ 설정됨 |
| Firebase Apple provider | ✅ 활성화 완료 |
| Apple Developer Sign In With Apple | ✅ 활성화 완료 |
| GoogleService-Info.plist | ✅ git 포함 |

---

## iOS 검은 화면 히스토리
→ `iOS_BLACK_SCREEN_DEBUG.md` 참고

## 출시 전 체크리스트
→ `memory/project_release_checklist.md` 참고
