// lib/data/alarm_settings_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../notifications/notification_planner.dart';

/// 알림 설정 영구 저장소(SharedPreferences)
/// - "적용"을 눌렀을 때만 저장
/// - 앱 재시작 후에도 마지막 적용값 복원
class AlarmSettingsRepository {
  static const _kWorkStartOn = 'alarm.workStartOn';
  static const _kWorkEndOn = 'alarm.workEndOn';
  static const _kPaydayOn = 'alarm.paydayOn';
  static const _kStartLeadMin = 'alarm.startLeadMinutes';
  static const _kEndLeadMin = 'alarm.endLeadMinutes';
  static const _kPaydayLeadDays = 'alarm.paydayLeadDays';

  /// 기본값(앱 첫 실행 시)
  static const AlarmSettings _defaults = AlarmSettings(
    workStartOn: false,
    workEndOn: false,
    paydayOn: false,
    startLeadMinutes: 10, // 1~60
    endLeadMinutes: 10, // 1~60
    paydayLeadDays: 0, // 0~15 (0=당일)
  );

  const AlarmSettingsRepository();

  /// 저장된 값을 읽어 AlarmSettings로 반환
  Future<AlarmSettings> load() async {
    final sp = await SharedPreferences.getInstance();

    final workStartOn = sp.getBool(_kWorkStartOn) ?? _defaults.workStartOn;
    final workEndOn = sp.getBool(_kWorkEndOn) ?? _defaults.workEndOn;
    final paydayOn = sp.getBool(_kPaydayOn) ?? _defaults.paydayOn;

    final startLead = sp.getInt(_kStartLeadMin) ?? _defaults.startLeadMinutes;
    final endLead = sp.getInt(_kEndLeadMin) ?? _defaults.endLeadMinutes;
    final paydayLead = sp.getInt(_kPaydayLeadDays) ?? _defaults.paydayLeadDays;

    // 안전 가드(허용 범위 밖이면 클램프)
    final startLeadClamped = startLead.clamp(1, 60);
    final endLeadClamped = endLead.clamp(1, 60);
    final paydayLeadClamped = paydayLead.clamp(0, 15);

    return AlarmSettings(
      workStartOn: workStartOn,
      workEndOn: workEndOn,
      paydayOn: paydayOn,
      startLeadMinutes: startLeadClamped,
      endLeadMinutes: endLeadClamped,
      paydayLeadDays: paydayLeadClamped,
    );
  }

  /// "적용" 버튼을 눌렀을 때만 호출해서 디스크에 반영
  Future<void> save(AlarmSettings settings) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kWorkStartOn, settings.workStartOn);
    await sp.setBool(_kWorkEndOn, settings.workEndOn);
    await sp.setBool(_kPaydayOn, settings.paydayOn);
    await sp.setInt(_kStartLeadMin, settings.startLeadMinutes.clamp(1, 60));
    await sp.setInt(_kEndLeadMin, settings.endLeadMinutes.clamp(1, 60));
    await sp.setInt(_kPaydayLeadDays, settings.paydayLeadDays.clamp(0, 15));
  }

  /// 모든 알림 설정 초기화(필요 시 사용)
  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kWorkStartOn);
    await sp.remove(_kWorkEndOn);
    await sp.remove(_kPaydayOn);
    await sp.remove(_kStartLeadMin);
    await sp.remove(_kEndLeadMin);
    await sp.remove(_kPaydayLeadDays);
  }
}
