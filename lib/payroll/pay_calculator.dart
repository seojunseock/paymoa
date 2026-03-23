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
  required SurchargePolicy policy, // 기본 정책 (이력 없을 때 폴백)
  int Function(String albaId, DateTime dateLocal)? wageAt,
  SurchargePolicy Function(DateTime date)? surchargeAt, // ✅ 날짜별 정책 이력
  TaxConfig Function(DateTime date)? taxAt, // ✅ 날짜별 세금 이력
  InsuranceConfig Function(DateTime date)? insuranceAt, // ✅ 날짜별 보험 이력
}) {
  final year = ymYear ?? ymDate?.year;
  final month = ymMonth ?? ymDate?.month;
  if (year == null || month == null) {
    return const MonthlySummary(gross: 0, net: 0);
  }

  final monthSchedules =
      schedules.where((s) => s.year == year && s.month == month).toList();

  // 주별 집계(주휴/주40) - ✅ 정책 변경일이 낀 주는 해당 날짜부터 다시 끊어서 집계
  final Map<DateTime, int> weeklyWorkedMinutes = {};
  final Map<DateTime, int> weeklyHolidayEligibleMinutes = {};
  final Map<DateTime, Set<String>> weeklyHolidayWorkDays = {};

  int gross = 0;
  final Map<DateTime, List<UICalendarSchedule>> weeklyScheduleMap = {};
  final Map<DateTime, List<UICalendarSchedule>> weeklyHolidayScheduleMap = {};

  for (final s in monthSchedules) {
    final pay = computeSinglePay(
      alba: alba,
      s: s,
      policy: policy,
      wageAt: wageAt,
      surchargeAt: surchargeAt, // ✅ 날짜별 정책
    );
    gross += pay;

    final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
    var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    final workedMin =
        max(0, end.difference(start).inMinutes - s.breakMinutes.clamp(0, 1440));

    final segmentStart = _weeklySegmentStart(
      day: DateTime(s.year, s.month, s.day),
      albaId: alba.id,
      baseHourlyWage: alba.hourlyWage,
      fallbackPolicy: policy,
      wageAt: wageAt,
      surchargeAt: surchargeAt,
    );

    // ✅ 주40 초과 연장 계산용: 전체 근무시간 유지
    weeklyWorkedMinutes[segmentStart] =
        (weeklyWorkedMinutes[segmentStart] ?? 0) + workedMin;
    (weeklyScheduleMap[segmentStart] ??= []).add(s);

    // ✅ 주휴 계산용: basic 근무만 포함
    if (s.workType == WorkType.basic) {
      weeklyHolidayEligibleMinutes[segmentStart] =
          (weeklyHolidayEligibleMinutes[segmentStart] ?? 0) + workedMin;
      (weeklyHolidayScheduleMap[segmentStart] ??= []).add(s);

      final dayKey = _ymdOf(DateTime(s.year, s.month, s.day));
      (weeklyHolidayWorkDays[segmentStart] ??= <String>{}).add(dayKey);
    }
  }

  // ✅ 주 40시간 초과 연장수당 - 정책 변경일 이후 segment 기준 계산
  weeklyWorkedMinutes.forEach((segmentStart, totalMins) {
    final weekPolicy = surchargeAt?.call(segmentStart) ?? policy;
    if (!weekPolicy.overtimeEnabled ||
        weekPolicy.overtimeRule != OvertimeRule.weeklyOver40) return;
    final overMins = max(0, totalMins - 40 * 60);
    if (overMins <= 0) return;

    final ws = weeklyScheduleMap[segmentStart] ?? [];
    final overrides =
        ws.map((s) => s.overrideHourlyWage).whereType<int>().toList();
    final refWage = overrides.isNotEmpty
        ? (overrides.reduce((a, b) => a + b) / overrides.length).round()
        : (wageAt?.call(alba.id, segmentStart) ?? alba.hourlyWage);

    gross += (refWage * (weekPolicy.overtimePercent / 100.0) * overMins / 60.0)
        .round();
  });

  // ✅ 주휴수당 - basic 근무만 segment 기준 계산
  weeklyHolidayEligibleMinutes.forEach((segmentStart, mins) {
    final weekPolicy = surchargeAt?.call(segmentStart) ?? policy;
    if (!weekPolicy.weeklyHolidayEnabled) return;
    if (mins < 15 * 60) return;

    final ws = weeklyHolidayScheduleMap[segmentStart] ?? [];
    final overrides =
        ws.map((s) => s.overrideHourlyWage).whereType<int>().toList();
    final refWage = overrides.isNotEmpty
        ? (overrides.reduce((a, b) => a + b) / overrides.length).round()
        : (wageAt?.call(alba.id, segmentStart) ?? alba.hourlyWage);

    final paidMinutes = _weeklyHolidayPaidMinutes(
      policy: weekPolicy,
      weekStart: segmentStart,
      weeklyWorkedMinutes: mins,
      weeklyWorkDays: weeklyHolidayWorkDays[segmentStart] ?? const <String>{},
    );

    gross += (refWage * (paidMinutes / 60.0)).round();
  });

  // ✅ 월 요약 세후는 해당 월 기준일 정책 사용
  final monthBaseDate = DateTime(year, month, 1);
  final effectiveTax = taxAt?.call(monthBaseDate) ?? tax;
  final effectiveInsurance = insuranceAt?.call(monthBaseDate) ?? insurance;

  final net = _applyTaxInsurance(
    gross: gross,
    tax: effectiveTax,
    insurance: effectiveInsurance,
  );
  return MonthlySummary(gross: gross, net: net);
}

int computeSinglePay({
  required UICalendarAlba alba,
  required UICalendarSchedule s,
  required SurchargePolicy policy, // 기본 정책 (이력 없을 때 폴백)
  int Function(String albaId, DateTime dateLocal)? wageAt,
  SurchargePolicy Function(DateTime date)? surchargeAt, // ✅ 날짜별 정책 이력
}) {
  final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
  var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

  // ✅ 날짜별 정책 이력 → 없으면 기본 policy 사용
  final scheduleDate = DateTime(s.year, s.month, s.day);
  final effectivePolicy = surchargeAt?.call(scheduleDate) ?? policy;

  // ✅ 우선순위: 스케줄별 override → wageAt(날짜별 시급) → 알바 기본 시급
  final baseWage = s.overrideHourlyWage ??
      (wageAt?.call(alba.id, scheduleDate) ?? alba.hourlyWage);

  final totalMin = end.difference(start).inMinutes;
  final workedMin = max(0, totalMin - s.breakMinutes.clamp(0, 1440));

  final basePay = (baseWage * workedMin / 60.0).round();

  int overtimePay = 0, nightPay = 0, holidayPay = 0;

  // ✅ 연장근로(옵션)
  if (effectivePolicy.overtimeEnabled) {
    final overtimeMin = _overtimeMinutes(
      policy: effectivePolicy,
      workedMin: workedMin,
      // weeklyOver40는 추후 period/week 집계 기반으로 확장
    );
    overtimePay = (baseWage *
            (effectivePolicy.overtimePercent / 100.0) *
            overtimeMin /
            60.0)
        .round();
  }

  // ✅ 야간근로(22:00~06:00)
  if (effectivePolicy.nightEnabled) {
    final nightMin = _overlapMinutesWithNight(start, end);
    nightPay =
        (baseWage * (effectivePolicy.nightPercent / 100.0) * nightMin / 60.0)
            .round();
  }

  // ✅ 휴일근로(“휴일=일요일 고정” 제거)
  if (effectivePolicy.holidayEnabled) {
    holidayPay = _holidayPremiumPay(
      baseWage: baseWage,
      start: start,
      end: end,
      policy: effectivePolicy,
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

  // 2026년 근로자 부담분
  // 고용보험: 0.9%
  // 4대보험: 국민연금 4.5% + 건강보험 3.545% + 고용보험 0.9% + 장기요양 0.4546% ≈ 9.4%
  double insPct = 0.0;
  if (insurance is InsuranceEmploymentOnly) insPct = 0.9;
  if (insurance is InsuranceFour) insPct = 9.4;

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

  // 근사(실무용): “그 주 주휴 카운트 대상 근로일수”로 나눈 평균 1일 근로시간
  final days = max(1, weeklyWorkDays.length);
  return max(0, (weeklyWorkedMinutes / days).round());
}

/* ─────────────────────────────
   overlap / sunday helpers
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

DateTime _sundayOf(DateTime d) {
  final dateOnly = DateTime(d.year, d.month, d.day);
  final daysFromSunday = d.weekday % 7; // 일요일=0, 월요일=1 ... 토요일=6
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

String _ymdOf(DateTime d) {
  final dd = DateTime(d.year, d.month, d.day);
  final y = dd.year.toString().padLeft(4, '0');
  final m = dd.month.toString().padLeft(2, '0');
  final day = dd.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
