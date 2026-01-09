// lib/data/in_memory_repository.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

/* ───────────────────────── Top-level DTOs (클래스 중첩 금지) ───────────────────────── */

class ValidationResult {
  final bool ok;
  final List<DateTime> conflictDates; // 로컬 날짜(yyyy-mm-dd 기준)
  const ValidationResult({required this.ok, required this.conflictDates});
}

class ScheduleBatchResult {
  final bool ok;
  final List<DateTime> conflictDates; // 로컬 날짜
  final List<UICalendarSchedule> inserted;
  const ScheduleBatchResult({
    required this.ok,
    required this.conflictDates,
    required this.inserted,
  });
}

/* ───────────────────────── Repository ───────────────────────── */

/// 아주 단순한 인메모리 저장소(앱 데모용)
class InMemoryRepository {
  final List<UICalendarAlba> _albas = [];
  final List<UICalendarSchedule> _schedules = [];

  final Map<String, TaxConfig> _taxByAlba = {};
  final Map<String, InsuranceConfig> _insByAlba = {};
  final Map<String, SurchargePolicy> _polByAlba = {};

  // 읽기용 뷰
  List<UICalendarAlba> get albas => List.unmodifiable(_albas);
  List<UICalendarSchedule> get schedules => List.unmodifiable(_schedules);

  // 정책 접근
  TaxConfig? taxOf(String albaId) => _taxByAlba[albaId];
  InsuranceConfig? insuranceOf(String albaId) => _insByAlba[albaId];
  SurchargePolicy? policyOf(String albaId) => _polByAlba[albaId];

  void setPolicies({
    required String albaId,
    required TaxConfig tax,
    required InsuranceConfig insurance,
    SurchargePolicy? surcharge,
  }) {
    _taxByAlba[albaId] = tax;
    _insByAlba[albaId] = insurance;
    if (surcharge != null) {
      _polByAlba[albaId] = surcharge;
    } else {
      _polByAlba.remove(albaId);
    }
  }

  // ---------------- 알바 ----------------

  void addAlba(UICalendarAlba alba) {
    _albas.add(_withIdIfEmptyAlba(alba));
  }

  void updateAlba(UICalendarAlba alba) {
    final idx = _albas.indexWhere((a) => a.id == alba.id);
    if (idx >= 0) _albas[idx] = alba;
  }

  void deleteAlba(String albaId) {
    _albas.removeWhere((a) => a.id == albaId);
    _schedules.removeWhere((s) => s.albaId == albaId);
    _taxByAlba.remove(albaId);
    _insByAlba.remove(albaId);
    _polByAlba.remove(albaId);
  }

  // ---------------- 스케줄 (단순 CRUD) ----------------

  void addSchedule(UICalendarSchedule sc) {
    _schedules.add(_withIdIfEmptySchedule(sc));
  }

  void updateSchedule(UICalendarSchedule sc) {
    final i = _schedules.indexWhere((e) => e.id == sc.id);
    if (i >= 0) _schedules[i] = sc;
  }

  void deleteSchedule(String scheduleId) {
    _schedules.removeWhere((e) => e.id == scheduleId);
  }

  // ---------------- 스케줄 (겹침 검사 유틸) ----------------
  //
  // 화면에서 전역 겹침 체크를 이미 하고 있지만,
  // 저장 전에 Repository 레벨에서도 재검사할 수 있게 유틸 제공.

  /// 주어진 시각(하루 동일 시간대)을 여러 날짜에 적용할 때, 기존 스케줄과 겹치는 날짜가 있는지 검사
  ValidationResult validateConflicts({
    required Set<DateTime> utcDates, // UTC 자정(yyyy-mm-dd)
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    int breakMinutes = 0, // 현재 겹침 여부엔 영향 없음
    String? excludeScheduleId, // 수정 시 자기 자신 제외
  }) {
    // 기준 시간대(분)
    final sMin0 = startHour * 60 + startMinute;
    var eMin0 = endHour * 60 + endMinute;
    if (eMin0 <= sMin0) eMin0 += 24 * 60; // 오버나이트 보정

    bool overlaps(int sA, int eA, int sB, int eB) => (sA < eB && sB < eA);

    bool dayHasConflict(DateTime localDay) {
      // 해당 일, 이전/다음 날의 기존 스케줄을 모아서 비교
      List<UICalendarSchedule> byYmd(DateTime x) => _schedules
          .where((s) => s.year == x.year && s.month == x.month && s.day == x.day)
          .toList();

      final same = byYmd(localDay);
      final prev = byYmd(DateTime(localDay.year, localDay.month, localDay.day - 1));
      final next = byYmd(DateTime(localDay.year, localDay.month, localDay.day + 1));

      bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
        for (final sc in list) {
          if (excludeScheduleId != null && sc.id == excludeScheduleId) continue;
          var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
          var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
          if (b <= a) b += 24 * 60; // 오버나이트 보정
          if (overlaps(sMin0, eMin0, a, b)) return true;
        }
        return false;
      }

      return overlapWith(same, 0) || overlapWith(prev, -1) || overlapWith(next, 1);
    }

    final hits = <DateTime>[];
    for (final utc in utcDates) {
      final local = DateTime(utc.year, utc.month, utc.day);
      if (dayHasConflict(local)) hits.add(local);
    }

    return ValidationResult(ok: hits.isEmpty, conflictDates: hits);
  }

  /// 날짜 여러 개에 동일 시간대 스케줄을 저장(검사 + 삽입)
  ScheduleBatchResult validateAndAddSchedules({
    required String albaId,
    required Set<DateTime> utcDates,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int breakMinutes,
    WorkType workType = WorkType.basic,
    int? overrideHourlyWage,
  }) {
    final v = validateConflicts(
      utcDates: utcDates,
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
      breakMinutes: breakMinutes,
    );
    if (!v.ok) {
      return ScheduleBatchResult(ok: false, conflictDates: v.conflictDates, inserted: const []);
    }

    final inserted = <UICalendarSchedule>[];
    for (final d in utcDates) {
      final sc = _withIdIfEmptySchedule(UICalendarSchedule(
        id: '',
        albaId: albaId,
        year: d.year,
        month: d.month,
        day: d.day,
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
        breakMinutes: breakMinutes,
        workType: workType,
        overrideHourlyWage: overrideHourlyWage,
      ));
      _schedules.add(sc);
      inserted.add(sc);
    }

    return ScheduleBatchResult(ok: true, conflictDates: const [], inserted: inserted);
  }

  /// 단일 스케줄 수정(검사 + 반영)
  ValidationResult validateAndUpdateSchedule(UICalendarSchedule sc) {
    final d = DateTime(sc.year, sc.month, sc.day);
    final v = validateConflicts(
      utcDates: {DateTime.utc(d.year, d.month, d.day)},
      startHour: sc.startHour,
      startMinute: sc.startMinute,
      endHour: sc.endHour,
      endMinute: sc.endMinute,
      breakMinutes: sc.breakMinutes,
      excludeScheduleId: sc.id, // 자기 자신 제외
    );
    if (!v.ok) return v;

    updateSchedule(sc);
    return const ValidationResult(ok: true, conflictDates: []);
  }
}

/* ───────────────────────── 내부 헬퍼: ID 자동 보정 ───────────────────────── */

UICalendarAlba _withIdIfEmptyAlba(UICalendarAlba a) {
  if (a.id.isNotEmpty) return a;
  // UICalendarAlba 필드 그대로 복사 + 새 ID
  return UICalendarAlba(
    id: _randId(),
    name: a.name,
    hourlyWage: a.hourlyWage,
    colorHex: a.colorHex,
    payDay: a.payDay,
  );
}

UICalendarSchedule _withIdIfEmptySchedule(UICalendarSchedule s) {
  if (s.id.isNotEmpty) return s;
  // UICalendarSchedule 필드 그대로 복사 + 새 ID
  return UICalendarSchedule(
    id: _randId(),
    albaId: s.albaId,
    year: s.year,
    month: s.month,
    day: s.day,
    startHour: s.startHour,
    startMinute: s.startMinute,
    endHour: s.endHour,
    endMinute: s.endMinute,
    breakMinutes: s.breakMinutes,
    // 아래 두 필드는 모델에 존재한다면 그대로 전달됩니다.
    // (모델에 없으면 컴파일러가 알려줄 테니 그때 주석 처리하세요.)
    overrideHourlyWage: s.overrideHourlyWage,
    workType: s.workType,
  );
}

String _randId() {
  final r = Random.secure();
  final b = List<int>.generate(12, (_) => r.nextInt(256));
  return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}
