# tools/emulator_fix/CleanNativeCaches.ps1
# Flutter(Android) 네이티브 캐시 정리 + 재빌드 (PowerShell 전용, CMD 아님)
# 사용 예:
#   powershell -ExecutionPolicy Bypass -File .\tools\emulator_fix\CleanNativeCaches.ps1

function Remove-Safe($path) {
    if (Test-Path -LiteralPath $path) {
        try {
            Write-Host "삭제: $path" -ForegroundColor Yellow
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            # 일부 잠금 파일이 있을 수 있음 → 무시
        }
    }
}

Write-Host "==> ADB 재시작" -ForegroundColor Cyan
try { adb kill-server | Out-Null } catch {}
try { adb start-server | Out-Null } catch {}

Write-Host "==> 네이티브/빌드 캐시 제거" -ForegroundColor Cyan
# 안드로이드 네이티브 캐시
Remove-Safe "android\app\.cxx"
Remove-Safe "android\.cxx"
Remove-Safe "android\.externalNativeBuild"

# 빌드 산출물
Remove-Safe "android\app\build"
Remove-Safe "build"

Write-Host "==> Flutter 클린/패키지 복구" -ForegroundColor Cyan
flutter clean
flutter pub get

Write-Host "==> 디버그 APK 재빌드" -ForegroundColor Cyan
flutter build apk --debug

Write-Host "`n완료. APK 경로 확인:" -ForegroundColor Green
Get-ChildItem "android\app\build\outputs\apk\debug" -ErrorAction SilentlyContinue
Write-Host "`n실행:" -ForegroundColor Green
Write-Host "flutter run -d emulator-5554" -ForegroundColor White
