// lib/payroll/payroll_engine.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

import 'pay_calculator.dart';
import 'payroll_policy.dart';

class PeriodSummary {
  final PayPeriod period;
  final DateTime payDate;
  final int gross;
  final int net;

  const PeriodSummary({
    required this.period,
    required this.payDate,
    required this.gross,
    required this.net,
  });
}

class PayrollEngine {
  const PayrollEngine();

  /// ✅ 다음 지급 미리보기 (UI 전용)
  List<PeriodPayPreview> previewNext({
    required PayrollPolicy policy,
    DateTime? from,
    int count = 3,
  }) {
    final base = _dateOnly(from ?? DateTime.now());
    final out = <PeriodPayPreview>[];

    DateTime cursor = base;
    while (out.length < count) {
      final preview =
          computePreviewForDate(policy: policy, anyDateInPeriod: cursor);

      if (out.isEmpty || preview.period.start != out.last.period.start) {
        out.add(preview);
      }

      // 다음 period 시작일로 점프
      cursor = _dateOnly(preview.period.end).add(const Duration(days: 1));
    }

    return out;
  }

  PeriodSummary summaryForDate({
    required PayrollPolicy policy,
    required UICalendarAlba alba,
    required List<UICalendarSchedule> schedules,
    required TaxConfig tax,
    required InsuranceConfig insurance,
    required SurchargePolicy surchargePolicy,
    int Function(String albaId, DateTime dateLocal)? wageAt,
    SurchargePolicy Function(DateTime date)? surchargeAt, // ✅ 날짜별 정책 이력
    TaxConfig Function(DateTime date)? taxAt, // ✅ 날짜별 세금
    InsuranceConfig Function(DateTime date)? insuranceAt, // ✅ 날짜별 보험
    DateTime? anyDateInPeriod,
  }) {
    final preview = computePreviewForDate(
      policy: policy,
      anyDateInPeriod: anyDateInPeriod ?? DateTime.now(),
    );

    // ✅ 급여 기간 시작일 기준으로 세금·보험 이력 조회
    final periodStart = preview.period.start;
    final effectiveTax = taxAt?.call(periodStart) ?? tax;
    final effectiveInsurance = insuranceAt?.call(periodStart) ?? insurance;

    final gross = _computeGrossForPeriod(
      alba: alba,
      schedules: schedules,
      period: preview.period,
      surchargePolicy: surchargePolicy,
      wageAt: wageAt,
      surchargeAt: surchargeAt,
    );

    final net = _applyTaxInsurance(
      gross: gross,
      tax: effectiveTax,
      insurance: effectiveInsurance,
    );

    return PeriodSummary(
      period: preview.period,
      payDate: preview.payDate,
      gross: gross,
      net: net,
    );
  }

  /* ───────── 내부 계산 ───────── */

  int _computeGrossForPeriod({
    required UICalendarAlba alba,
    required List<UICalendarSchedule> schedules,
    required PayPeriod period,
    required SurchargePolicy surchargePolicy,
    int Function(String albaId, DateTime dateLocal)? wageAt,
    SurchargePolicy Function(DateTime date)? surchargeAt, // ✅ 날짜별 정책
  }) {
    final periodStart = _dateOnly(period.start);
    final periodEndExclusive =
        _dateOnly(period.end).add(const Duration(days: 1));

    final targetSchedules = schedules.where((s) {
      if (s.albaId != alba.id) return false;
      final (schStart, schEnd) = _scheduleRange(s);
      return _rangesOverlap(
        aStart: schStart,
        aEnd: schEnd,
        bStart: periodStart,
        bEnd: periodEndExclusive,
      );
    }).toList();

    int gross = 0;
    final Map<DateTime, int> weeklyWorkedMinutes = {};
    final Map<DateTime, int> weeklyHolidayEligibleMinutes = {};
    final Map<DateTime, Set<String>> weeklyHolidayWorkDays = {};
    final Map<DateTime, List<UICalendarSchedule>> weeklyScheduleMap = {};
    final Map<DateTime, List<UICalendarSchedule>> weeklyHolidayScheduleMap = {};

    for (final s in targetSchedules) {
      gross += computeSinglePay(
        alba: alba,
        s: s,
        policy: surchargePolicy,
        wageAt: wageAt,
        surchargeAt: surchargeAt, // ✅ 날짜별 정책 이력 전달
      );

      final (schStart, schEnd) = _scheduleRange(s);
      final workedMin = _workedMinutes(schStart, schEnd, s.breakMinutes);

      final segmentStart = _weeklySegmentStart(
        day: DateTime(s.year, s.month, s.day),
        albaId: alba.id,
        baseHourlyWage: alba.hourlyWage,
        fallbackPolicy: surchargePolicy,
        wageAt: wageAt,
        surchargeAt: surchargeAt,
      );

      // ✅ 주40 연장 계산용: 전체 근무시간 유지
      weeklyWorkedMinutes[segmentStart] =
          (weeklyWorkedMinutes[segmentStart] ?? 0) + workedMin;
      (weeklyScheduleMap[segmentStart] ??= <UICalendarSchedule>[]).add(s);

      // ✅ 주휴 계산용: 카운트 대상 근무만 포함
      if (s.workType == WorkType.basic) {
        weeklyHolidayEligibleMinutes[segmentStart] =
            (weeklyHolidayEligibleMinutes[segmentStart] ?? 0) + workedMin;
        (weeklyHolidayScheduleMap[segmentStart] ??= <UICalendarSchedule>[])
            .add(s);
        (weeklyHolidayWorkDays[segmentStart] ??= <String>{})
            .add(_ymdOf(schStart));
      }
    }

    // ✅ 주휴수당 - basic 근무만, 일~토 segment 기준 계산
    weeklyHolidayEligibleMinutes.forEach((segmentStart, mins) {
      final weekPolicy = surchargeAt?.call(segmentStart) ?? surchargePolicy;
      if (!weekPolicy.weeklyHolidayEnabled) return;
      if (mins < 15 * 60) return;

      final ws = weeklyHolidayScheduleMap[segmentStart] ??
          const <UICalendarSchedule>[];
      final overrides =
          ws.map((s) => s.overrideHourlyWage).whereType<int>().toList();
      final refWage = overrides.isNotEmpty
          ? (overrides.reduce((a, b) => a + b) / overrides.length).round()
          : (wageAt?.call(alba.id, segmentStart) ?? alba.hourlyWage);

      final paidMinutes = weekPolicy.weeklyHolidayUseFixedMinutes
          ? weekPolicy.weeklyHolidayFixedMinutes
          : min(8 * 60, (mins * 8 / 40).round());

      gross += (refWage * (paidMinutes / 60)).round();
    });

    // ✅ 주 40시간 초과 연장수당 - 기존처럼 전체 근무시간 기준
    weeklyWorkedMinutes.forEach((segmentStart, totalMins) {
      final weekPolicy = surchargeAt?.call(segmentStart) ?? surchargePolicy;
      if (!weekPolicy.overtimeEnabled ||
          weekPolicy.overtimeRule != OvertimeRule.weeklyOver40) {
        return;
      }
      final overMins = max(0, totalMins - 40 * 60);
      if (overMins <= 0) return;

      final ws =
          weeklyScheduleMap[segmentStart] ?? const <UICalendarSchedule>[];
      final overrides =
          ws.map((s) => s.overrideHourlyWage).whereType<int>().toList();
      final refWage = overrides.isNotEmpty
          ? (overrides.reduce((a, b) => a + b) / overrides.length).round()
          : (wageAt?.call(alba.id, segmentStart) ?? alba.hourlyWage);

      gross +=
          (refWage * (weekPolicy.overtimePercent / 100.0) * overMins / 60.0)
              .round();
    });

    return gross;
  }

  int _applyTaxInsurance({
    required int gross,
    required TaxConfig tax,
    required InsuranceConfig insurance,
  }) {
    double taxPct = 0;
    if (tax == TaxConfig.biz33) taxPct = 3.3;
    if (tax == TaxConfig.day66) taxPct = 6.6;
    if (tax is TaxConfigCustomPercent) taxPct = tax.percent;

    // 2026년 근로자 부담분
    // 고용보험: 0.9%
    // 4대보험: 국민연금 4.5% + 건강보험 3.545% + 고용보험 0.9% + 장기요양 0.4546% ≈ 9.4%
    double insPct = 0;
    if (insurance is InsuranceEmploymentOnly) insPct = 0.9;
    if (insurance is InsuranceFour) insPct = 9.4;

    return (gross * (1 - (taxPct + insPct) / 100)).round();
  }

  /* ───────── util ───────── */

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  (DateTime, DateTime) _scheduleRange(UICalendarSchedule s) {
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

  int _workedMinutes(DateTime start, DateTime end, int breakMinutes) {
    return max(
      0,
      end.difference(start).inMinutes - breakMinutes.clamp(0, 1440),
    );
  }

  DateTime _sundayOf(DateTime d) {
    final dateOnly = DateTime(d.year, d.month, d.day);
    final daysFromSunday = d.weekday % 7; // 일요일=0 ... 토요일=6
    return dateOnly.subtract(Duration(days: daysFromSunday));
  }

  DateTime _weeklySegmentStart({
    required DateTime day,
    required String albaId,
    required int baseHourlyWage,
    required SurchargePolicy fallbackPolicy,
    int Function(String albaId, DateTime dateLocal)? wageAt,
    SurchargePolicy Function(DateTime date)? surchargeAt,
  }) {
    final target = DateTime(day.year, day.month, day.day);
    final sunday = _sundayOf(target);

    var segmentStart = sunday;
    var prevPolicy = surchargeAt?.call(sunday) ?? fallbackPolicy;
    var prevWage = wageAt?.call(albaId, sunday) ?? baseHourlyWage;

    for (var cursor = sunday.add(const Duration(days: 1));
        !cursor.isAfter(target);
        cursor = cursor.add(const Duration(days: 1))) {
      final currentPolicy = surchargeAt?.call(cursor) ?? fallbackPolicy;
      final currentWage = wageAt?.call(albaId, cursor) ?? baseHourlyWage;

      final policyChanged = !_sameWeeklyPolicy(prevPolicy, currentPolicy);
      final wageChanged = prevWage != currentWage;

      if (policyChanged || wageChanged) {
        segmentStart = cursor;
      }

      prevPolicy = currentPolicy;
      prevWage = currentWage;
    }

    return segmentStart;
  }

  bool _sameWeeklyPolicy(SurchargePolicy a, SurchargePolicy b) {
    return a.weeklyHolidayEnabled == b.weeklyHolidayEnabled &&
        a.weeklyHolidayUseFixedMinutes == b.weeklyHolidayUseFixedMinutes &&
        a.weeklyHolidayFixedMinutes == b.weeklyHolidayFixedMinutes &&
        a.overtimeEnabled == b.overtimeEnabled &&
        a.overtimeRule == b.overtimeRule &&
        a.overtimePercent == b.overtimePercent;
  }

  String _ymdOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
