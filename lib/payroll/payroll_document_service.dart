// lib/payroll/payroll_document_service.dart
import 'dart:math';

import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';

import '../models/ui_calendar_models.dart';

import '../policies/policies.dart';
import '../policies/policy_mapper.dart' as pm;

import 'payroll_engine.dart';
import 'payroll_policy.dart';
import 'pay_calculator.dart';

/// ✅ 문서(엑셀/PDF/CSV) 생성용 “한 방 입력/출력”
///
/// - UI/문서 금액 불일치 방지: 계산은 PayrollEngine / pay_calculator를 재사용
class PayrollDocumentService {
  final PayrollEngine _engine;

  const PayrollDocumentService({PayrollEngine? engine})
      : _engine = engine ?? const PayrollEngine();

  /// ✅ (1) 지급분(정산기간) 기준 문서
  List<PayrollDocumentRow> buildPeriodDocument({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required PayPeriod period,
  }) {
    final Map<String, List<StoreSchedule>> byWorker = {};
    for (final s in schedules) {
      (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
    }

    final rows = <PayrollDocumentRow>[];

    for (final w in workers) {
      final ws = byWorker[w.workerUid] ?? const <StoreSchedule>[];

      final effectiveWage = _effectiveWage(store: store, worker: w);
      final effectivePayDay = _effectivePayDay(store: store, worker: w);
      final tax = _effectiveTax(store: store, worker: w);
      final insurance = _effectiveInsurance(store: store, worker: w);
      final surcharge = _effectiveSurcharge(store: store, worker: w);

      final basePolicy = store.payrollPolicy;
      final policy = basePolicy.copyWith(
        payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
      );

      // period에 겹치는 스케줄만 필터
      final filtered = _filterSchedulesByPeriod(ws, period);
      final uiSchedules = filtered.map(_toUiSchedule).toList(growable: false);

      final alba = UICalendarAlba(
        id: w.workerUid,
        storeId: store.id,
        name: (w.displayName ?? w.workerUid),
        hourlyWage: effectiveWage,
        colorHex: 'FF000000',
        payDay: effectivePayDay,
      );

      // ✅ 날짜별 시급·가산정책 이력 콜백 (카드 화면과 동일 계산 보장)
      int wageAtFn(String _, DateTime date) =>
          w.effectiveHourlyWageAt(store, date);
      SurchargePolicy surchargeAtFn(DateTime date) =>
          w.policyHistory.surchargeAt(date) ?? surcharge;

      // ✅ 지급분 계산은 엔진을 그대로 사용
      final summary = _engine.summaryForDate(
        policy: policy,
        alba: alba,
        schedules: uiSchedules,
        tax: tax,
        insurance: insurance,
        surchargePolicy: surcharge,
        wageAt: wageAtFn,
        surchargeAt: surchargeAtFn,
        anyDateInPeriod: period.start,
      );

      final workedMinutes = _sumWorkedMinutesLikeEngine(filtered);

      rows.add(
        PayrollDocumentRow(
          kind: PayrollDocumentKind.period,
          storeId: store.id,
          storeName: store.name,
          workerUid: w.workerUid,
          workerName: (w.displayName ?? w.workerUid),
          periodStart: summary.period.start,
          periodEnd: summary.period.end,
          payDate: summary.payDate,
          hourlyWage: effectiveWage,
          workedMinutes: workedMinutes,
          scheduleCount: filtered.length,
          gross: summary.gross,
          net: summary.net,
          tax: tax,
          insurance: insurance,
          surcharge: surcharge,
          payrollPolicy: policy,
        ),
      );
    }

    rows.sort((a, b) {
      final an = a.workerName.trim();
      final bn = b.workerName.trim();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return a.workerUid.compareTo(b.workerUid);
    });

    return rows;
  }

  /// ✅ (2) “년도+월” 기준 문서 (캘린더 월 내역)
  ///
  /// - month는 사용자가 선택
  /// - 계산은 computeMonthlySummary() 재사용
  /// - ⚠️ payDate는 "해당 월에 대한 정책상 지급일"로 계산해야 일관됨
  List<PayrollDocumentRow> buildCalendarMonthDocument({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int month,
  }) {
    final Map<String, List<StoreSchedule>> byWorker = {};
    for (final s in schedules) {
      (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
    }

    final rows = <PayrollDocumentRow>[];

    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month, _daysInMonth(year, month));

    for (final w in workers) {
      final wsAll = byWorker[w.workerUid] ?? const <StoreSchedule>[];

      // ✅ 해당 월에 속한 스케줄만
      final ws = wsAll
          .where((s) => s.year == year && s.month == month)
          .toList(growable: false);

      final effectiveWage = _effectiveWage(store: store, worker: w);
      final effectivePayDay = _effectivePayDay(store: store, worker: w);
      final tax = _effectiveTax(store: store, worker: w);
      final insurance = _effectiveInsurance(store: store, worker: w);
      final surcharge = _effectiveSurcharge(store: store, worker: w);

      // payrollPolicy 스냅샷(문서 메타로 보관) + 지급일만 덮기
      final basePolicy = store.payrollPolicy;
      final policy = basePolicy.copyWith(
        payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
      );

      final uiSchedules = ws.map(_toUiSchedule).toList(growable: false);

      final alba = UICalendarAlba(
        id: w.workerUid,
        storeId: store.id,
        name: (w.displayName ?? w.workerUid),
        hourlyWage: effectiveWage,
        colorHex: 'FF000000',
        payDay: effectivePayDay,
      );

      // ✅ 날짜별 시급·가산정책 이력 콜백 (카드 화면과 동일 계산 보장)
      int wageAtFn(String _, DateTime date) =>
          w.effectiveHourlyWageAt(store, date);
      SurchargePolicy surchargeAtFn(DateTime date) =>
          w.policyHistory.surchargeAt(date) ?? surcharge;

      final monthSummary = computeMonthlySummary(
        alba: alba,
        ymYear: year,
        ymMonth: month,
        schedules: uiSchedules,
        tax: tax,
        insurance: insurance,
        policy: surcharge,
        wageAt: wageAtFn,
        surchargeAt: surchargeAtFn,
      );

      final workedMinutes = _sumWorkedMinutesMonthly(ws);

      // ✅ 중요: 월 문서의 payDate도 “정책 기반”으로 계산 (불일치 방지)
      final preview =
          computePreviewForDate(policy: policy, anyDateInPeriod: monthStart);
      final payDate = preview.payDate;

      rows.add(
        PayrollDocumentRow(
          kind: PayrollDocumentKind.calendarMonth,
          storeId: store.id,
          storeName: store.name,
          workerUid: w.workerUid,
          workerName: (w.displayName ?? w.workerUid),
          periodStart: monthStart,
          periodEnd: monthEnd,
          payDate: payDate,
          hourlyWage: effectiveWage,
          workedMinutes: workedMinutes,
          scheduleCount: ws.length,
          gross: monthSummary.gross,
          net: monthSummary.net,
          tax: tax,
          insurance: insurance,
          surcharge: surcharge,
          payrollPolicy: policy,
        ),
      );
    }

    rows.sort((a, b) {
      final an = a.workerName.trim();
      final bn = b.workerName.trim();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return a.workerUid.compareTo(b.workerUid);
    });

    return rows;
  }

  /* ─────────────────────────────────────────
     helpers
  ────────────────────────────────────────── */

  List<StoreSchedule> _filterSchedulesByPeriod(
    List<StoreSchedule> src,
    PayPeriod period,
  ) {
    final pStart = _dateOnly(period.start);
    final pEndEx = _dateOnly(period.end).add(const Duration(days: 1));

    final out = <StoreSchedule>[];
    for (final s in src) {
      final (schStart, schEnd) = _storeScheduleRange(s);
      if (_rangesOverlap(
        aStart: schStart,
        aEnd: schEnd,
        bStart: pStart,
        bEnd: pEndEx,
      )) {
        out.add(s);
      }
    }

    out.sort((a, b) {
      final ak = a.year * 10000 + a.month * 100 + a.day;
      final bk = b.year * 10000 + b.month * 100 + b.day;
      if (ak != bk) return ak.compareTo(bk);
      final am = a.startHour * 60 + a.startMinute;
      final bm = b.startHour * 60 + b.startMinute;
      return am.compareTo(bm);
    });

    return out;
  }

  int _sumWorkedMinutesLikeEngine(List<StoreSchedule> schedules) {
    int sum = 0;
    for (final s in schedules) {
      final (schStart, schEnd) = _storeScheduleRange(s);
      final totalMin = schEnd.difference(schStart).inMinutes;
      final workedMin = max(0, totalMin - s.breakMinutes.clamp(0, 1440));
      sum += workedMin;
    }
    return sum;
  }

  int _sumWorkedMinutesMonthly(List<StoreSchedule> schedules) {
    return _sumWorkedMinutesLikeEngine(schedules);
  }

  (DateTime start, DateTime end) _storeScheduleRange(StoreSchedule s) {
    final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
    var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start, end);
  }

  bool _rangesOverlap({
    required DateTime aStart,
    required DateTime aEnd,
    required DateTime bStart,
    required DateTime bEnd,
  }) {
    final s = aStart.isAfter(bStart) ? aStart : bStart;
    final e = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    return e.isAfter(s);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _daysInMonth(int y, int m) {
    final firstNext = (m == 12) ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  UICalendarSchedule _toUiSchedule(StoreSchedule s) {
    return UICalendarSchedule(
      id: s.id,
      albaId: s.workerUid,
      year: s.year,
      month: s.month,
      day: s.day,
      startHour: s.startHour,
      startMinute: s.startMinute,
      endHour: s.endHour,
      endMinute: s.endMinute,
      breakMinutes: s.breakMinutes,
      workType: _mapWorkType(s.workType),
      overrideHourlyWage: s.overrideHourlyWage, // ✅ 날짜별 시급 반영
    );
  }

  WorkType _mapWorkType(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'substitute':
        return WorkType.substitute;
      case 'night':
        return WorkType.night;
      case 'overtime':
        return WorkType.overtime;
      case 'holiday':
        return WorkType.holiday;
      case 'basic':
      default:
        return WorkType.basic;
    }
  }

  /* ─────────────────────────────────────────
     effective resolvers (OwnerStoreDetailScreen과 동일)
  ────────────────────────────────────────── */

  int _effectiveWage({required Store store, required StoreWorker worker}) {
    final int? storeWage = store.defaultHourlyWage;
    return worker.inheritFromStore
        ? (storeWage ?? worker.hourlyWage ?? 0)
        : (worker.hourlyWage ?? storeWage ?? 0);
  }

  int _effectivePayDay({required Store store, required StoreWorker worker}) {
    final int? storePayDay = store.payDay;
    final resolved = worker.inheritFromStore
        ? (storePayDay ?? worker.payDay ?? 15)
        : (worker.payDay ?? storePayDay ?? 15);
    return resolved.clamp(1, 31);
  }

  TaxConfig _effectiveTax({required Store store, required StoreWorker worker}) {
    final base = store.taxConfig;

    final o = worker.policyOverride;
    if (o == null) return base;

    final rawTax = o['tax'];
    if (rawTax == null) return base;

    return pm.taxConfigFromAny(rawTax);
  }

  InsuranceConfig _effectiveInsurance({
    required Store store,
    required StoreWorker worker,
  }) {
    final base = store.insuranceConfig;

    final o = worker.policyOverride;
    if (o == null) return base;

    final raw = o['insurance'];
    if (raw == null) return base;

    return pm.insuranceConfigFromAny(raw);
  }

  SurchargePolicy _effectiveSurcharge({
    required Store store,
    required StoreWorker worker,
  }) {
    if (worker.inheritFromStore) return store.surchargePolicy;

    final root = worker.policyOverride ?? const <String, dynamic>{};
    return pm.surchargePolicyFromAny(root['surcharge']);
  }
}

enum PayrollDocumentKind {
  period,
  calendarMonth,
}

/// ✅ 엑셀/문서 출력용 Row 모델
class PayrollDocumentRow {
  final PayrollDocumentKind kind;

  final String storeId;
  final String storeName;

  final String workerUid;
  final String workerName;

  final DateTime periodStart; // 포함
  final DateTime periodEnd; // 포함
  final DateTime payDate;

  final int hourlyWage;
  final int workedMinutes;
  final int scheduleCount;

  final int gross;
  final int net;

  final TaxConfig tax;
  final InsuranceConfig insurance;
  final SurchargePolicy surcharge;
  final PayrollPolicy payrollPolicy;

  const PayrollDocumentRow({
    required this.kind,
    required this.storeId,
    required this.storeName,
    required this.workerUid,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.hourlyWage,
    required this.workedMinutes,
    required this.scheduleCount,
    required this.gross,
    required this.net,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.payrollPolicy,
  });

  int get workedHoursFloor => workedMinutes ~/ 60;
  int get workedMinutesRemainder => workedMinutes % 60;

  String get workedTimeText =>
      '${workedHoursFloor}시간 ${workedMinutesRemainder}분';

  static String fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toExcelMap() {
    return {
      'kind': kind.name,
      'storeName': storeName,
      'workerName': workerName,
      'periodStart': fmtDate(periodStart),
      'periodEnd': fmtDate(periodEnd),
      'payDate': fmtDate(payDate),
      'hourlyWage': hourlyWage,
      'scheduleCount': scheduleCount,
      'workedMinutes': workedMinutes,
      'workedTime': workedTimeText,
      'gross': gross,
      'net': net,
    };
  }
}
