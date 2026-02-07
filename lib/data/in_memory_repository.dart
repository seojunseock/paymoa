// lib/data/in_memory_repository.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';
import '../payroll/payroll.dart';

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

class InMemoryRepository {
  final List<UICalendarStore> _stores = [];
  final List<UICalendarAlba> _albas = [];
  final List<UICalendarSchedule> _schedules = [];

  final Map<String, TaxConfig> _taxByAlba = {};
  final Map<String, InsuranceConfig> _insByAlba = {};
  final Map<String, SurchargePolicy> _polByAlba = {};

  final Map<String, TaxConfig> _taxByStore = {};
  final Map<String, InsuranceConfig> _insByStore = {};
  final Map<String, SurchargePolicy> _polByStore = {};

  // ✅ payroll: 매장 기본 + 알바 override
  final Map<String, PayrollPolicy> _payrollByStore = {};
  final Map<String, PayrollPolicy> _payrollOverrideByAlba = {};

  // 읽기용 뷰
  List<UICalendarStore> get stores => List.unmodifiable(_stores);
  List<UICalendarAlba> get albas => List.unmodifiable(_albas);
  List<UICalendarSchedule> get schedules => List.unmodifiable(_schedules);

  /* ───────────────── 정책 접근 ───────────────── */

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

  TaxConfig? defaultTaxOfStore(String storeId) => _taxByStore[storeId];
  InsuranceConfig? defaultInsuranceOfStore(String storeId) =>
      _insByStore[storeId];
  SurchargePolicy? defaultPolicyOfStore(String storeId) => _polByStore[storeId];

  void setStoreDefaults({
    required String storeId,
    required TaxConfig tax,
    required InsuranceConfig insurance,
    SurchargePolicy? surcharge,
  }) {
    _taxByStore[storeId] = tax;
    _insByStore[storeId] = insurance;
    if (surcharge != null) {
      _polByStore[storeId] = surcharge;
    } else {
      _polByStore.remove(storeId);
    }
  }

  // ✅ payroll 기본/override setter
  PayrollPolicy? defaultPayrollOfStore(String storeId) =>
      _payrollByStore[storeId];

  void setStorePayrollDefault({
    required String storeId,
    required PayrollPolicy policy,
  }) {
    _payrollByStore[storeId] = policy;
  }

  PayrollPolicy? payrollOverrideOfAlba(String albaId) =>
      _payrollOverrideByAlba[albaId];

  void setAlbaPayrollOverride({
    required String albaId,
    PayrollPolicy? override,
  }) {
    if (override == null) {
      _payrollOverrideByAlba.remove(albaId);
    } else {
      _payrollOverrideByAlba[albaId] = override;
    }
  }

  // ✅ payroll effective
  PayrollPolicy? effectivePayrollOfAlba(String albaId) {
    final alba = _albas.firstWhere(
      (a) => a.id == albaId,
      orElse: () => const UICalendarAlba(
        id: '',
        storeId: '',
        name: '',
        hourlyWage: 0,
        colorHex: '#3B82F6',
        payDay: 25,
      ),
    );
    if (alba.id.isEmpty) return null;

    return _payrollOverrideByAlba[albaId] ?? _payrollByStore[alba.storeId];
  }

  TaxConfig effectiveTaxOfAlba(String albaId) {
    final alba = _albas.firstWhere(
      (a) => a.id == albaId,
      orElse: () => const UICalendarAlba(
        id: '',
        storeId: '',
        name: '',
        hourlyWage: 0,
        colorHex: '#3B82F6',
        payDay: 25,
      ),
    );
    if (alba.id.isEmpty) return TaxConfig.none;
    return _taxByAlba[albaId] ?? (_taxByStore[alba.storeId] ?? TaxConfig.none);
  }

  InsuranceConfig effectiveInsuranceOfAlba(String albaId) {
    final alba = _albas.firstWhere(
      (a) => a.id == albaId,
      orElse: () => const UICalendarAlba(
        id: '',
        storeId: '',
        name: '',
        hourlyWage: 0,
        colorHex: '#3B82F6',
        payDay: 25,
      ),
    );
    if (alba.id.isEmpty) return const InsuranceNone();
    return _insByAlba[albaId] ??
        (_insByStore[alba.storeId] ?? const InsuranceNone());
  }

  SurchargePolicy effectivePolicyOfAlba(String albaId) {
    final alba = _albas.firstWhere(
      (a) => a.id == albaId,
      orElse: () => const UICalendarAlba(
        id: '',
        storeId: '',
        name: '',
        hourlyWage: 0,
        colorHex: '#3B82F6',
        payDay: 25,
      ),
    );
    if (alba.id.isEmpty) return const SurchargePolicy();
    return _polByAlba[albaId] ??
        (_polByStore[alba.storeId] ?? const SurchargePolicy());
  }

  /* ───────────────── 매장(Store) ───────────────── */

  void addStore(UICalendarStore store) {
    final fixed = _withIdIfEmptyStore(
      store,
      existingCodes: _stores.map((s) => s.storeCode).toSet(),
    );
    _stores.add(fixed);

    _taxByStore.putIfAbsent(fixed.id, () => TaxConfig.none);
    _insByStore.putIfAbsent(fixed.id, () => const InsuranceNone());

    // ✅ payroll 기본값(없으면 기본 월급/25일 정도로 초기화)
    _payrollByStore.putIfAbsent(fixed.id, () {
      final now = DateTime.now();
      return PayrollPolicy(
        cycle: PayCycleType.monthly,
        startFrom: DateTime(now.year, now.month, now.day),
        monthlyStartDay: 1,
        payRule: PayDateRule.nextMonthlyDay(fixed.payDay),
      );
    });
  }

  void updateStore(UICalendarStore store) {
    final idx = _stores.indexWhere((s) => s.id == store.id);
    if (idx >= 0) _stores[idx] = store;
  }

  void deleteStore(String storeId) {
    _stores.removeWhere((s) => s.id == storeId);

    final albaIds =
        _albas.where((a) => a.storeId == storeId).map((a) => a.id).toSet();
    _albas.removeWhere((a) => a.storeId == storeId);
    _schedules.removeWhere((sc) => albaIds.contains(sc.albaId));

    for (final id in albaIds) {
      _taxByAlba.remove(id);
      _insByAlba.remove(id);
      _polByAlba.remove(id);
      _payrollOverrideByAlba.remove(id);
    }

    _taxByStore.remove(storeId);
    _insByStore.remove(storeId);
    _polByStore.remove(storeId);
    _payrollByStore.remove(storeId);
  }

  UICalendarStore? findStoreByCode(String code) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    try {
      return _stores.firstWhere((s) => s.storeCode.trim().toUpperCase() == c);
    } catch (_) {
      return null;
    }
  }

  List<UICalendarAlba> albasByStore(String storeId) =>
      _albas.where((a) => a.storeId == storeId).toList(growable: false);

  /* ───────────────── 알바(Alba) ───────────────── */

  void addAlba(UICalendarAlba alba) {
    // ✅ storeId가 비어 있으면 “첫 매장”으로 자동 보정
    final fixed = _normalizeAlbaStoreId(alba);
    _albas.add(_withIdIfEmptyAlba(fixed));
  }

  void updateAlba(UICalendarAlba alba) {
    final idx = _albas.indexWhere((a) => a.id == alba.id);
    if (idx >= 0) _albas[idx] = _normalizeAlbaStoreId(alba);
  }

  void deleteAlba(String albaId) {
    _albas.removeWhere((a) => a.id == albaId);
    _schedules.removeWhere((s) => s.albaId == albaId);
    _taxByAlba.remove(albaId);
    _insByAlba.remove(albaId);
    _polByAlba.remove(albaId);
    _payrollOverrideByAlba.remove(albaId);
  }

  UICalendarAlba _normalizeAlbaStoreId(UICalendarAlba alba) {
    final sid = alba.storeId.trim();
    if (sid.isNotEmpty) return alba;

    if (_stores.isEmpty) {
      throw StateError('매장이 없습니다. 먼저 매장을 등록한 뒤 알바를 추가하세요.');
    }
    return alba.copyWith(storeId: _stores.first.id);
  }

  /* ───────────────── 스케줄 CRUD ───────────────── */

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

  /* ───────────────── 스케줄 겹침 검사 유틸 ───────────────── */

  ValidationResult validateConflicts({
    required Set<DateTime> utcDates,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    int breakMinutes = 0,
    String? excludeScheduleId,
  }) {
    final sMin0 = startHour * 60 + startMinute;
    var eMin0 = endHour * 60 + endMinute;
    if (eMin0 <= sMin0) eMin0 += 24 * 60;

    bool overlaps(int sA, int eA, int sB, int eB) => (sA < eB && sB < eA);

    bool dayHasConflict(DateTime localDay) {
      List<UICalendarSchedule> byYmd(DateTime x) => _schedules
          .where(
              (s) => s.year == x.year && s.month == x.month && s.day == x.day)
          .toList();

      final same = byYmd(localDay);
      final prev =
          byYmd(DateTime(localDay.year, localDay.month, localDay.day - 1));
      final next =
          byYmd(DateTime(localDay.year, localDay.month, localDay.day + 1));

      bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
        for (final sc in list) {
          if (excludeScheduleId != null && sc.id == excludeScheduleId) continue;
          var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
          var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
          if (b <= a) b += 24 * 60;
          if (overlaps(sMin0, eMin0, a, b)) return true;
        }
        return false;
      }

      return overlapWith(same, 0) ||
          overlapWith(prev, -1) ||
          overlapWith(next, 1);
    }

    final hits = <DateTime>[];
    for (final utc in utcDates) {
      final local = DateTime(utc.year, utc.month, utc.day);
      if (dayHasConflict(local)) hits.add(local);
    }

    return ValidationResult(ok: hits.isEmpty, conflictDates: hits);
  }

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
      return ScheduleBatchResult(
          ok: false, conflictDates: v.conflictDates, inserted: const []);
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

    return ScheduleBatchResult(
        ok: true, conflictDates: const [], inserted: inserted);
  }

  ValidationResult validateAndUpdateSchedule(UICalendarSchedule sc) {
    final d = DateTime(sc.year, sc.month, sc.day);
    final v = validateConflicts(
      utcDates: {DateTime.utc(d.year, d.month, d.day)},
      startHour: sc.startHour,
      startMinute: sc.startMinute,
      endHour: sc.endHour,
      endMinute: sc.endMinute,
      breakMinutes: sc.breakMinutes,
      excludeScheduleId: sc.id,
    );
    if (!v.ok) return v;

    updateSchedule(sc);
    return const ValidationResult(ok: true, conflictDates: []);
  }
}

/* ───────────────────────── 내부 헬퍼: ID/코드 자동 보정 ───────────────────────── */

UICalendarStore _withIdIfEmptyStore(
  UICalendarStore s, {
  required Set<String> existingCodes,
}) {
  final id = s.id.isNotEmpty ? s.id : _randId();

  String code = s.storeCode.trim();
  if (code.isEmpty || existingCodes.contains(code)) {
    code = _randStoreCode(existingCodes);
  }

  return UICalendarStore(
    id: id,
    name: s.name,
    storeCode: code,
    defaultHourlyWage: s.defaultHourlyWage,
    payDay: s.payDay,
  );
}

UICalendarAlba _withIdIfEmptyAlba(UICalendarAlba a) {
  if (a.id.isNotEmpty) return a;
  return UICalendarAlba(
    id: _randId(),
    storeId: a.storeId,
    name: a.name,
    hourlyWage: a.hourlyWage,
    colorHex: a.colorHex,
    payDay: a.payDay,
  );
}

UICalendarSchedule _withIdIfEmptySchedule(UICalendarSchedule s) {
  if (s.id.isNotEmpty) return s;
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
    overrideHourlyWage: s.overrideHourlyWage,
    workType: s.workType,
  );
}

String _randId() {
  final r = Random.secure();
  final b = List<int>.generate(12, (_) => r.nextInt(256));
  return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

String _randStoreCode(Set<String> existing) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();

  String gen() {
    final sb = StringBuffer();
    for (int i = 0; i < 8; i++) {
      sb.write(chars[r.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  var code = gen();
  var guard = 0;
  while (existing.contains(code) && guard < 1000) {
    code = gen();
    guard++;
  }
  return code;
}
