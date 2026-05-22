# iOS 검은 화면 디버깅 파일
> Mac 세션에서 이 파일 먼저 열 것. 목표: 원인 파악 → TestFlight에서 화면 나오면 즉시 종료

---

## 핵심 상황 요약

| 항목 | 내용 |
|------|------|
| 증상 | TestFlight 설치 후 앱 실행 시 검은 화면 |
| 기기 | iPhone 16 Pro, iOS 18.x |
| Android | 완전 정상 |
| Flutter | 3.29.2 |
| 빌드 도구 | Codemagic M2 (Xcode 16.2) |
| 크래시 여부 | 크래시 없음 — 상태바 보임, 앱 살아있음 |
| 결론 | Flutter 렌더링 자체 불가. Dart/Firebase/Kakao 코드 문제 아님 |

---

## 지금까지 시도한 것 (빌드 1~75)

| 시도 | 결과 |
|------|------|
| Firebase 제거 | 검은 화면 지속 |
| Kakao 제거 | 검은 화면 지속 |
| 빌드 47: 초록 화면만 출력 (Hello World 수준) | 검은 화면 지속 → Dart 코드 문제 아님 확정 |
| FLTEnableImpeller = false (Impeller 비활성화) | 검은 화면 지속 |
| CADisableMinimumFrameDurationOnPhone 키 시도 | 효과 없음 |
| Codemagic M2 빌드 | 검은 화면 지속 |
| GitHub Actions 빌드 | 검은 화면 지속 |

결정적 사실: 빌드 47에서 Flutter 초록 화면 한 줄짜리 앱도 검은 화면 → Flutter 엔진이 iOS 18에서 렌더링을 못 하는 것

---

## Mac에서 할 것 (순서대로, 시간 아끼기)

### STEP 1 — Flutter 업그레이드 후 빌드 (30분)

```bash
flutter upgrade
flutter --version   # 버전 메모

flutter clean
cd ios && pod install && cd ..
flutter build ios --release --no-codesign
```

빌드 성공하면 STEP 2로

---

### STEP 2 — Xcode에서 Archive + TestFlight 업로드 (30분)

```bash
open ios/Runner.xcworkspace
```

Xcode에서:
1. Product → Archive
2. Distribute App → App Store Connect → Upload
3. TestFlight에서 설치 → 화면 나오는지 확인

화면 나오면 → 즉시 종료. 안드로이드 작업으로 복귀.

---

### STEP 3 — 화면 안 나오면: Xcode 콘솔 로그 분석 (30분)

iPhone 연결 후:
```
Xcode → Window → Devices and Simulators
→ 기기 선택 → Open Console
→ 앱 실행
→ 아래 키워드 검색
```

찾아야 할 키워드:
- dyld → 라이브러리 링크 문제
- SIGABRT, SIGSEGV, EXC_BAD_ACCESS → 크래시 원인
- flutter, engine → Flutter 엔진 에러
- metal, gpu → GPU/렌더링 문제
- libflutter → Flutter 라이브러리 로드 실패

로그 복사해서 Claude Code에 붙여넣으면 원인 분석해줌

---

### STEP 4 — 그래도 안 되면: flutter channel beta 시도

```bash
flutter channel beta
flutter upgrade
flutter clean
cd ios && pod install && cd ..
```

---

## 원인 가설 (현재 유력한 것)

1. iOS 18 + Flutter 3.29.2 호환성 문제 → Flutter 업그레이드로 해결 가능성 높음
2. Metal 렌더러 초기화 실패 → iPhone 16 Pro GPU 드라이버 충돌
3. Codemagic 빌드 환경 문제 → Xcode 직접 빌드로 비교 필요

---

## 비용 현황 (CI/CD)

| 서비스 | 상태 |
|--------|------|
| Codemagic 무료 500분 | 소진 + $10 추가 사용 |
| GitHub Actions | 이번 달 소진 (매달 리셋) |
| Mac 직접 빌드 | 무료 |

---

## 화면 나오면 즉시 할 것

1. 해결된 Flutter 버전 메모
2. git push
3. TestFlight 빌드 번호 기록
4. 이 파일 아래 해결 기록란 채우기
5. 안드로이드 작업으로 복귀

---

## 해결 후 기록란 (내일 채울 것)

- 해결된 빌드 번호:
- Flutter 버전:
- 원인:
- 해결 방법:
