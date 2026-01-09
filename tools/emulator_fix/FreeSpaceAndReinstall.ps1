# tools/emulator_fix/FreeSpaceAndReinstall.ps1
# Paycount Flutter - 에뮬레이터 저장공간 부족/강제종료 자동 복구 스크립트 (Windows PowerShell)
# 사용법(프로젝트 루트에서):
#   powershell -ExecutionPolicy Bypass -File .\tools\emulator_fix\FreeSpaceAndReinstall.ps1 `
#     -DeviceId emulator-5554 `
#     -PackageName com.paycount.app `
#     -ApkPath android\app\build\outputs\apk\debug\app-debug.apk

param(
  [string]$DeviceId = "emulator-5554",
  [string]$PackageName = "com.paycount.app",
  [string]$ApkPath = "android\app\build\outputs\apk\debug\app-debug.apk"
)

function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }

# 0) 필수 도구 확인
try { flutter --version | Out-Null } catch { throw "Flutter CLI를 찾을 수 없습니다. PATH를 확인하세요." }
Step "ADB 서버 재시작"
adb kill-server | Out-Null
adb start-server | Out-Null

# 1) 디바이스 확인
$devs = (adb devices) -join "`n"
if ($devs -notmatch $DeviceId) {
  Write-Warning "[$DeviceId] 가 보이지 않습니다. Android Studio → Device Manager에서 AVD를 먼저 실행하세요."
  adb devices
  exit 1
}
Step "대상 디바이스: $DeviceId 확인 완료"

# 2) 기존 앱 강제 제거 (일반/유저0 둘 다 시도)
Step "기존 앱 제거: $PackageName"
adb -s $DeviceId uninstall $PackageName | Out-Null
adb -s $DeviceId shell pm uninstall -k --user 0 $PackageName | Out-Null

# 3) 임시파일/캐시 정리 (설치 실패 원인 1순위)
Step "임시폴더/캐시 정리"
adb -s $DeviceId shell rm -rf /data/local/tmp/* 2>$null
adb -s $DeviceId shell rm -rf /sdcard/Download/* 2>$null
adb -s $DeviceId shell "pm trim-caches 100G" 2>$null

# 4) 저장공간 상황 표시(참고)
Step "저장공간 확인"
adb -s $DeviceId shell df -h | findstr /I "/data /sdcard"

# 5) APK 존재 확인 후 재설치
if (-not (Test-Path $ApkPath)) {
  throw "APK 경로가 존재하지 않습니다: $ApkPath (먼저 flutter build apk --debug 실행하세요)"
}
Step "APK 재설치: $ApkPath"
adb -s $DeviceId install -r -t "$ApkPath"

# 6) 설치 결과 안내
if ($LASTEXITCODE -eq 0) {
  Step "설치 성공. 앱 실행 로그를 보려면 아래를 별도 터미널에서 실행하세요:"
  Write-Host "adb logcat | Select-String -Pattern 'FATAL EXCEPTION|AndroidRuntime'"
} else {
  Write-Warning "설치 실패. 여전히 INSTALL_FAILED_INSUFFICIENT_STORAGE가 뜨면 AVD Wipe Data 후 재시도하세요."
}
