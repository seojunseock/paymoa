// lib/data/in_memory_repository.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

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

  // ---------------- 스케줄 ----------------

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
}

// ---- 내부 헬퍼: ID 자동 보정 ----

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
