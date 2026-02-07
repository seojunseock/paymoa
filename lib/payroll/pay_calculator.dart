// lib/payroll/pay_calculator.dart
import 'dart:math';
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

class MonthlySummary {
  final int gross; // 세전
  final int net; // 세후
  const MonthlySummary({required this.gross, required this.net});
}

MonthlySummary computeMonthlySummary({
  required UICalendarAlba alba,
  int? ymYear,
  int? ymMonth,
  DateTime? ymDate,
  required List<UICalendarSchedule> schedules,
  required TaxConfig tax,
  required InsuranceConfig insurance,
  required SurchargePolicy policy,
  int Function(String albaId, DateTime dateLocal)? wageAt,
}) {
  final year = ymYear ?? ymDate?.year;
  final month = ymMonth ?? ymDate?.month;
  if (year == null || month == null) {
    return const MonthlySummary(gross: 0, net: 0);
  }

  final monthSchedules =
      schedules.where((s) => s.year == year && s.month == month).toList();

  // 주별 집계(주휴)
  final Map<DateTime, int> weeklyMinutes = {}; // key: 주시작(월요일 00:00)
  final Map<DateTime, Set<String>> weeklyWorkDays = {}; // 주별 근로일(날짜 set)

  int gross = 0;

  for (final s in monthSchedules) {
    final pay =
        computeSinglePay(alba: alba, s: s, policy: policy, wageAt: wageAt);
    gross += pay;

    final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
    var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    final workedMin =
        end.difference(start).inMinutes - s.breakMinutes.clamp(0, 1440);

    final weekStart = _mondayOf(start);
    weeklyMinutes[weekStart] = (weeklyMinutes[weekStart] ?? 0) + workedMin;

    // 근로일(시작일 기준)만 MVP로 카운트(실무에서 충분히 안정적)
    final dayKey = _ymdOf(DateTime(s.year, s.month, s.day));
    (weeklyWorkDays[weekStart] ??= <String>{}).add(dayKey);
  }

  // ✅ 주휴수당 (한국: 1주 소정근로시간 15시간 이상이면 발생)
  if (policy.weeklyHolidayEnabled) {
    weeklyMinutes.forEach((weekStart, mins) {
      if (mins >= 15 * 60) {
        final refWage = wageAt?.call(alba.id, weekStart) ?? alba.hourlyWage;

        final paidMinutes = _weeklyHolidayPaidMinutes(
          policy: policy,
          weekStart: weekStart,
          weeklyWorkedMinutes: mins,
          weeklyWorkDays: weeklyWorkDays[weekStart] ?? const <String>{},
        );

        gross += (refWage * (paidMinutes / 60.0)).round();
      }
    });
  }

  final net = _applyTaxInsurance(gross: gross, tax: tax, insurance: insurance);
  return MonthlySummary(gross: gross, net: net);
}

int computeSinglePay({
  required UICalendarAlba alba,
  required UICalendarSchedule s,
  required SurchargePolicy policy,
  int Function(String albaId, DateTime dateLocal)? wageAt,
}) {
  final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
  var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

  final baseWage = wageAt?.call(alba.id, DateTime(s.year, s.month, s.day)) ??
      alba.hourlyWage;

  final totalMin = end.difference(start).inMinutes;
  final workedMin = max(0, totalMin - s.breakMinutes.clamp(0, 1440));

  final basePay = (baseWage * workedMin / 60.0).round();

  int overtimePay = 0, nightPay = 0, holidayPay = 0;

  // ✅ 연장근로(옵션)
  if (policy.overtimeEnabled) {
    final overtimeMin = _overtimeMinutes(
      policy: policy,
      workedMin: workedMin,
      // weeklyOver40는 추후 period/week 집계 기반으로 확장
    );
    overtimePay =
        (baseWage * (policy.overtimePercent / 100.0) * overtimeMin / 60.0)
            .round();
  }

  // ✅ 야간근로(22:00~06:00)
  if (policy.nightEnabled) {
    final nightMin = _overlapMinutesWithNight(start, end);
    nightPay =
        (baseWage * (policy.nightPercent / 100.0) * nightMin / 60.0).round();
  }

  // ✅ 휴일근로(“휴일=일요일 고정” 제거)
  if (policy.holidayEnabled) {
    holidayPay = _holidayPremiumPay(
      baseWage: baseWage,
      start: start,
      end: end,
      policy: policy,
    );
  }

  return basePay + overtimePay + nightPay + holidayPay;
}

/* ─────────────────────────────
   Tax / Insurance
───────────────────────────── */

int _applyTaxInsurance({
  required int gross,
  required TaxConfig tax,
  required InsuranceConfig insurance,
}) {
  double taxPct = 0.0;
  if (tax == TaxConfig.biz33) taxPct = 3.3;
  if (tax == TaxConfig.day66) taxPct = 6.6;
  if (tax is TaxConfigCustomPercent) taxPct = tax.percent;

  double insPct = 0.0;
  if (insurance is InsuranceEmploymentOnly) insPct = 1.0;
  if (insurance is InsuranceFour) insPct = 8.0;

  return (gross * (1 - (taxPct + insPct) / 100.0)).round();
}

/* ─────────────────────────────
   Overtime
───────────────────────────── */

int _overtimeMinutes({
  required SurchargePolicy policy,
  required int workedMin,
}) {
  switch (policy.overtimeRule) {
    case OvertimeRule.dailyOver8:
      return max(0, workedMin - 8 * 60);

    case OvertimeRule.weeklyOver40:
      // 고급옵션: 주 40시간 초과분 계산은 “주 집계”가 필요
      // -> 지금은 안전하게 0으로 처리(정확한 구현은 PayrollEngine 레벨에서)
      return 0;
  }
}

/* ─────────────────────────────
   Holiday / Night
───────────────────────────── */

int _holidayPremiumPay({
  required int baseWage,
  required DateTime start,
  required DateTime end,
  required SurchargePolicy policy,
}) {
  // 휴일에 해당하는 “분”을 날짜 단위로 쪼개서 계산(8시간 구간 분리 가능)
  int premiumPay = 0;

  DateTime cursor = start;
  while (cursor.isBefore(end)) {
    final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final segEnd = end.isBefore(dayEnd) ? end : dayEnd;

    final minutesInThisDay = _overlapMinutes(start, end, cursor, segEnd);
    if (minutesInThisDay > 0 && _isHolidayDay(dayStart, policy)) {
      if (!policy.holidayUseKoreanLawTier) {
        // 전 구간 동일 가산
        premiumPay += (baseWage *
                (policy.holidayPercent / 100.0) *
                minutesInThisDay /
                60.0)
            .round();
      } else {
        // ✅ 한국식 2단계: 8시간 이내 / 8시간 초과
        final first = min(8 * 60, minutesInThisDay);
        final rest = max(0, minutesInThisDay - first);

        final p1 = policy.holidayPercent;
        final p2 = max(policy.holidayPercent, 100); // 초과분은 최소 100%로

        if (first > 0) {
          premiumPay += (baseWage * (p1 / 100.0) * first / 60.0).round();
        }
        if (rest > 0) {
          premiumPay += (baseWage * (p2 / 100.0) * rest / 60.0).round();
        }
      }
    }

    cursor = segEnd;
  }

  return premiumPay;
}

bool _isHolidayDay(DateTime dayStart, SurchargePolicy policy) {
  // 1) 매장 주휴일(기본: 일요일)
  if (dayStart.weekday == policy.weeklyHolidayWeekday) return true;

  // 2) 추가 휴일(약정휴일/공휴일 수기등록 등)
  final key = _ymdOf(dayStart);
  if (policy.extraHolidayYmds.contains(key)) return true;

  return false;
}

int _overlapMinutesWithNight(DateTime start, DateTime end) {
  int sum = 0;

  final nightStart1 = DateTime(start.year, start.month, start.day, 22, 0);
  final nightEnd1 = DateTime(start.year, start.month, start.day, 24, 0);
  sum += _overlapMinutes(start, end, nightStart1, nightEnd1);

  final next =
      DateTime(start.year, start.month, start.day).add(const Duration(days: 1));
  final nightStart2 = DateTime(next.year, next.month, next.day, 0, 0);
  final nightEnd2 = DateTime(next.year, next.month, next.day, 6, 0);
  sum += _overlapMinutes(start, end, nightStart2, nightEnd2);

  return sum;
}

/* ─────────────────────────────
   Weekly holiday minutes
───────────────────────────── */

int _weeklyHolidayPaidMinutes({
  required SurchargePolicy policy,
  required DateTime weekStart,
  required int weeklyWorkedMinutes,
  required Set<String> weeklyWorkDays,
}) {
  if (policy.weeklyHolidayUseFixedMinutes) {
    return max(0, policy.weeklyHolidayFixedMinutes);
  }

  // 근사(실무용): “그 주 근로일수”로 나눈 평균 1일 근로시간
  // - 법의 디테일(소정근로시간/근로형태)은 고급옵션에서 더 확장
  final days = max(1, weeklyWorkDays.length);
  return max(0, (weeklyWorkedMinutes / days).round());
}

/* ─────────────────────────────
   overlap / monday helpers
───────────────────────────── */

int _overlapMinutes(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  final s = aStart.isAfter(bStart) ? aStart : bStart;
  final e = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final diff = e.difference(s).inMinutes;
  return diff > 0 ? diff : 0;
}

DateTime _mondayOf(DateTime d) {
  return DateTime(d.year, d.month, d.day)
      .subtract(Duration(days: d.weekday - 1));
}

String _ymdOf(DateTime d) {
  final dd = DateTime(d.year, d.month, d.day);
  final y = dd.year.toString().padLeft(4, '0');
  final m = dd.month.toString().padLeft(2, '0');
  final day = dd.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
