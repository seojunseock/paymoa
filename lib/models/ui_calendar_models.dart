// lib/models/ui_calendar_models.dart
import 'package:flutter/foundation.dart';

/// 근무 타입(가산정책 계산에서 사용)
enum WorkType { basic, substitute, night, overtime, holiday }

extension WorkTypeWeeklyHolidayX on WorkType {
  bool get countsForWeeklyHoliday {
    switch (this) {
      case WorkType.basic:
        return true;
      case WorkType.substitute:
      case WorkType.night:
      case WorkType.overtime:
      case WorkType.holiday:
        return false;
    }
  }
}

/// ✅ 매장(사장님 기준 최상위)
@immutable
class UICalendarStore {
  final String id;
  final String name;

  /// 공유 코드(알바생이 입력/QR로 참여)
  final String storeCode;

  /// 매장 기본값(알바가 별도 설정 안 하면 이 값 사용 가능)
  final int defaultHourlyWage;
  final int payDay;

  const UICalendarStore({
    required this.id,
    required this.name,
    required this.storeCode,
    required this.defaultHourlyWage,
    required this.payDay,
  });

  UICalendarStore copyWith({
    String? id,
    String? name,
    String? storeCode,
    int? defaultHourlyWage,
    int? payDay,
  }) {
    return UICalendarStore(
      id: id ?? this.id,
      name: name ?? this.name,
      storeCode: storeCode ?? this.storeCode,
      defaultHourlyWage: defaultHourlyWage ?? this.defaultHourlyWage,
      payDay: payDay ?? this.payDay,
    );
  }
}

/// ✅ 알바
/// - storeId는 추후 Firestore에서 강제될 값이지만,
///   지금은 기존 화면들이 깨지지 않도록 기본값 ''(빈값)을 허용한다.
@immutable
class UICalendarAlba {
  final String id;

  /// ✅ 호환 패치: 기본값 '' 허용
  final String storeId;

  final String name;

  /// 알바 개인 시급(유지)
  final int hourlyWage;

  final String colorHex;
  final int payDay;

  const UICalendarAlba({
    required this.id,
    this.storeId = '',
    required this.name,
    required this.hourlyWage,
    required this.colorHex,
    required this.payDay,
  });

  UICalendarAlba copyWith({
    String? id,
    String? storeId,
    String? name,
    int? hourlyWage,
    String? colorHex,
    int? payDay,
  }) {
    return UICalendarAlba(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      hourlyWage: hourlyWage ?? this.hourlyWage,
      colorHex: colorHex ?? this.colorHex,
      payDay: payDay ?? this.payDay,
    );
  }
}

/// 달력에 표시되는 근무 스케줄(알바 1명에 종속)
@immutable
class UICalendarSchedule {
  final String id;

  /// ✅ albaId = 개인알바면 myAlbas의 albaId
  /// ✅ 조인알바면 storeId(=join의 storeId)
  final String albaId;

  final int year;
  final int month;
  final int day;

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  final int breakMinutes;

  final WorkType workType;

  /// 해당 근무만 시급 오버라이드(선택)
  final int? overrideHourlyWage;

  /// ✅ (핵심) Firestore 문서 경로
  /// - 개인 스케줄: users/{uid}/mySchedules/{id}
  /// - 조인 스케줄: users/{ownerUid}/stores/{storeId}/schedules/{id}
  ///
  /// 이게 있으면 "고아 스케줄"도 경로로 바로 삭제 가능.
  final String? docPath;

  const UICalendarSchedule({
    required this.id,
    required this.albaId,
    required this.year,
    required this.month,
    required this.day,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.breakMinutes,
    this.workType = WorkType.basic,
    this.overrideHourlyWage,
    this.docPath, // ✅ 추가
  });

  bool get countsForWeeklyHoliday => workType.countsForWeeklyHoliday;

  /// ✅ copyWith에서 overrideHourlyWage를 "null로 리셋"할 수 있게 처리
  /// - overrideHourlyWage: 그대로 두고 싶으면 전달하지 않으면 됨
  /// - resetOverrideHourlyWage: true면 overrideHourlyWage를 null로 만든다
  UICalendarSchedule copyWith({
    String? id,
    String? albaId,
    int? year,
    int? month,
    int? day,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    int? breakMinutes,
    WorkType? workType,
    int? overrideHourlyWage,
    bool resetOverrideHourlyWage = false,
    String? docPath,
  }) {
    return UICalendarSchedule(
      id: id ?? this.id,
      albaId: albaId ?? this.albaId,
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      workType: workType ?? this.workType,
      overrideHourlyWage: resetOverrideHourlyWage
          ? null
          : (overrideHourlyWage ?? this.overrideHourlyWage),
      docPath: docPath ?? this.docPath,
    );
  }
}
