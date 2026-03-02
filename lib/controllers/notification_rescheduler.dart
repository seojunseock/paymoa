// lib/controllers/notification_rescheduler.dart
import 'dart:async';

/// 스케줄/정책 변경 시 알림 재설정을 "디바운스 + 중복 제거"로 안정화하기 위한 유틸.
/// - UI에서 로직을 빼고, 한 군데에서만 재스케줄링 규칙을 적용하기 위해 만듭니다.
class NotificationRescheduler {
  NotificationRescheduler({
    Duration debounce = const Duration(milliseconds: 250),
  }) : _debounce = debounce;

  final Duration _debounce;

  Timer? _timer;
  String? _lastSignature;

  /// signature가 같으면 같은 변경으로 보고 재실행을 막습니다(중복 방지).
  void schedule({
    required String signature,
    required Future<void> Function() action,
  }) {
    if (_lastSignature == signature) return;
    _lastSignature = signature;

    _timer?.cancel();
    _timer = Timer(_debounce, () async {
      try {
        await action();
      } catch (_) {
        // 알림 재설정 실패는 앱 크래시로 이어지지 않게 삼킵니다.
        // (2차에서 로깅/리포팅 연결)
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
