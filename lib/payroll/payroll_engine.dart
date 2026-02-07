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
    DateTime? anyDateInPeriod,
  }) {
    final preview = computePreviewForDate(
      policy: policy,
      anyDateInPeriod: anyDateInPeriod ?? DateTime.now(),
    );

    final gross = _computeGrossForPeriod(
      alba: alba,
      schedules: schedules,
      period: preview.period,
      surchargePolicy: surchargePolicy,
      wageAt: wageAt,
    );

    final net =
        _applyTaxInsurance(gross: gross, tax: tax, insurance: insurance);

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
    final Map<DateTime, int> weeklyMinutes = {};
    final Map<DateTime, Set<String>> weeklyWorkDays = {};

    for (final s in targetSchedules) {
      gross += computeSinglePay(
        alba: alba,
        s: s,
        policy: surchargePolicy,
        wageAt: wageAt,
      );

      final (schStart, schEnd) = _scheduleRange(s);
      final workedMin = _workedMinutes(schStart, schEnd, s.breakMinutes);

      final weekStart = _sundayOf(schStart);
      weeklyMinutes[weekStart] = (weeklyMinutes[weekStart] ?? 0) + workedMin;

      (weeklyWorkDays[weekStart] ??= <String>{}).add(_ymdOf(schStart));
    }

    if (surchargePolicy.weeklyHolidayEnabled) {
      weeklyMinutes.forEach((weekStart, mins) {
        if (mins >= 15 * 60) {
          final refWage = wageAt?.call(alba.id, weekStart) ?? alba.hourlyWage;

          final days = max(1, weeklyWorkDays[weekStart]?.length ?? 1);

          final paidMinutes = surchargePolicy.weeklyHolidayUseFixedMinutes
              ? surchargePolicy.weeklyHolidayFixedMinutes
              : (mins / days).round();

          gross += (refWage * (paidMinutes / 60)).round();
        }
      });
    }

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

    double insPct = 0;
    if (insurance is InsuranceEmploymentOnly) insPct = 1.0;
    if (insurance is InsuranceFour) insPct = 8.0;

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
        0, end.difference(start).inMinutes - breakMinutes.clamp(0, 1440));
  }

  DateTime _sundayOf(DateTime d) {
    final x = _dateOnly(d);
    return x.subtract(Duration(days: x.weekday % 7));
  }

  String _ymdOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
