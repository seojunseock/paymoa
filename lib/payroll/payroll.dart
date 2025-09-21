import 'dart:math';
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

class MonthlySummary {
  final int gross; // 세전
  final int net;   // 세후
  const MonthlySummary({required this.gross, required this.net});
}

/// “하우머치” 수준의 간단 합계:
/// - 폼에서 설정한 가산정책(주휴/연장/휴일/야간)을 반영
/// - 세금/보험은 간이 비율
/// - 연장: 1회 근무 8시간 초과분에 적용
/// - 야간: 22:00~06:00 겹치는 분수에 적용(오버나이트 보정)
/// - 휴일: 일요일 구간에 적용
/// - 주휴: 주(월~일) 15시간 이상이면 8시간×시급 추가
///
/// 추가:
/// - [wageAt]가 주어지면 날짜별 시급을 사용(없으면 alba.hourlyWage)
MonthlySummary computeMonthlySummary({
  required UICalendarAlba alba,
  int? ymYear,
  int? ymMonth,
  DateTime? ymDate,
  required List<UICalendarSchedule> schedules,
  required TaxConfig tax,
  required InsuranceConfig insurance,
  required SurchargePolicy policy,

  /// (선택) 날짜별 시급 조회: (albaId, localDate) -> wage
  int Function(String albaId, DateTime dateLocal)? wageAt,
}) {
  final year = ymYear ?? ymDate?.year;
  final month = ymMonth ?? ymDate?.month;
  if (year == null || month == null) {
    return const MonthlySummary(gross: 0, net: 0);
  }

  // 해당 월 스케줄만
  final monthSchedules =
      schedules.where((s) => s.year == year && s.month == month).toList();

  // 주(월~일)별 총 근로 분 집계 (주휴 판단용)
  final Map<DateTime, int> weeklyMinutes = {}; // key: 주시작(월요일 00:00)

  int gross = 0;

  // ----- 스케줄 단위 기본/가산 계산 -----
  for (final s in monthSchedules) {
    // 스케줄 시작/끝 (로컬)
    final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
    var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // 오버나이트

    // 날짜별 시급 (없으면 기본 시급)
    final baseWage = wageAt?.call(alba.id, DateTime(s.year, s.month, s.day))
        ?? alba.hourlyWage;

    final totalMin = end.difference(start).inMinutes;
    final workedMin = max(0, totalMin - s.breakMinutes);

    // 기본 임금
    final basePay = (baseWage * workedMin / 60).round();

    // 연장(8시간 초과) 분
    int overtimeMin = 0;
    if (policy.overtimeEnabled) {
      overtimeMin = max(0, workedMin - 8 * 60);
    }

    // 야간(22:00~06:00) 겹치는 분
    int nightMin = 0;
    if (policy.nightEnabled) {
      nightMin = _overlapMinutesWithNight(start, end);
    }

    // 휴일(일요일) 겹치는 분
    int holidayMin = 0;
    if (policy.holidayEnabled) {
      holidayMin = _overlapMinutesWithSunday(start, end);
    }

    // 가산 임금들
    final overtimePay =
        (baseWage * (policy.overtimePercent / 100.0) * overtimeMin / 60).round();
    final nightPay =
        (baseWage * (policy.nightPercent / 100.0) * nightMin / 60).round();
    final holidayPay =
        (baseWage * (policy.holidayPercent / 100.0) * holidayMin / 60).round();

    gross += basePay + overtimePay + nightPay + holidayPay;

    // 주(월~일) 집계(주휴 판단)
    final weekStart = _mondayOf(start);
    weeklyMinutes[weekStart] = (weeklyMinutes[weekStart] ?? 0) + workedMin;
  }

  // ----- 주휴수당(주 15시간 이상시 8시간분 지급) -----
  if (policy.weeklyHolidayEnabled) {
    weeklyMinutes.forEach((weekStart, mins) {
      if (mins >= 15 * 60) {
        // 주휴도 날짜별 시급을 쓰려면 그 주의 평균 시급 등이 필요하지만,
        // 하우머치 목적이라 기본 시급 or 그 주 첫날 시급으로 단순화.
        final refDate = weekStart;
        final refWage = wageAt?.call(alba.id, refDate) ?? alba.hourlyWage;
        gross += (refWage * 8); // 8시간 × 시급
      }
    });
  }

  // ----- 세금/보험(간이) -----
  double taxPct = 0.0;
  if (tax == TaxConfig.biz33) taxPct = 3.3;
  if (tax == TaxConfig.day66) taxPct = 6.6;
  if (tax is TaxConfigCustomPercent) taxPct = tax.percent;

  double insPct = 0.0;
  if (insurance is InsuranceEmploymentOnly) insPct = 1.0;
  if (insurance is InsuranceFour) insPct = 8.0;

  final net = (gross * (1 - (taxPct + insPct) / 100)).round();
  return MonthlySummary(gross: gross, net: net);
}

/// 스케줄 [start, end) 와 야간 구간(매일 22:00~24:00, 다음날 00:00~06:00)의 겹치는 분
int _overlapMinutesWithNight(DateTime start, DateTime end) {
  int sum = 0;

  // 당일 22~24
  final nightStart1 = DateTime(start.year, start.month, start.day, 22, 0);
  final nightEnd1   = DateTime(start.year, start.month, start.day, 24, 0);
  sum += _overlapMinutes(start, end, nightStart1, nightEnd1);

  // 다음날 00~06
  final next = DateTime(start.year, start.month, start.day).add(const Duration(days: 1));
  final nightStart2 = DateTime(next.year, next.month, next.day, 0, 0);
  final nightEnd2   = DateTime(next.year, next.month, next.day, 6, 0);
  sum += _overlapMinutes(start, end, nightStart2, nightEnd2);

  return sum;
}

/// 스케줄 [start, end) 와 일요일 구간의 겹치는 분
int _overlapMinutesWithSunday(DateTime start, DateTime end) {
  int sum = 0;

  // 시작날
  final dayStart = DateTime(start.year, start.month, start.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  if (dayStart.weekday == DateTime.sunday) {
    sum += _overlapMinutes(start, end, dayStart, dayEnd);
  }

  // 자정을 넘어간 경우 다음날도 확인
  final nextDay = DateTime(end.year, end.month, end.day);
  if (nextDay != dayStart && nextDay.weekday == DateTime.sunday) {
    final nextEnd = nextDay.add(const Duration(days: 1));
    sum += _overlapMinutes(start, end, nextDay, nextEnd);
  }
  return sum;
}

/// [aStart,aEnd) 와 [bStart,bEnd) 의 겹치는 분
int _overlapMinutes(
    DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final s = aStart.isAfter(bStart) ? aStart : bStart;
  final e = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final diff = e.difference(s).inMinutes;
  return diff > 0 ? diff : 0;
}

/// 해당 날짜가 속한 주의 “월요일 00:00”
DateTime _mondayOf(DateTime d) {
  // DateTime.weekday: Mon=1 ... Sun=7
  return DateTime(d.year, d.month, d.day)
      .subtract(Duration(days: d.weekday - 1));
}
