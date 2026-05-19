// lib/services/update_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// 강제 인앱 업데이트 서비스 (Android)
/// - Play Store에 신버전이 있으면 즉시 전체화면 업데이트 UI 표시
/// - 사용자가 "나중에" 선택 불가 — 업데이트 완료 전까지 앱 사용 불가
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  bool _checked = false;

  /// 앱 실행 후 세션당 1회만 확인 (Android only)
  Future<void> checkOnce(BuildContext context) async {
    if (_checked) return;
    _checked = true;

    if (!Platform.isAndroid) return;

    await _checkAndroid(context);
  }

  Future<void> _checkAndroid(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      // 즉시 업데이트: 전체화면 Play Store UI, 사용자가 닫을 수 없음
      await InAppUpdate.performImmediateUpdate();
    } catch (_) {
      // 에뮬레이터 / 사이드로드 환경에서는 무시
    }
  }
}
