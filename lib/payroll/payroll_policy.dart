// lib/payroll/payroll_policy.dart

/// 정산 주기
enum PayCycleType {
  monthly, // 1개월 (달력월)
  weekly, // 1주  (✅ 일요일 시작 고정)
  twoWeeks, // 2주 (✅ 사용자가 선택한 "시작 일요일" 기준)
  daily, // 1일 (단기)
  customDays, // 레거시/확장용
}

enum WeeklyAnchor {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

/// 지급일 규칙
enum PayDateRuleType {
  nextMonthlyDay, // period.end 다음날 이후 처음 오는 "매월 day"
  samePeriodEndDay, // 정산 종료일 당일
  afterEndPlusDays, // 종료 후 N일
  fixedDate, // 특정 날짜(1회성)
}

class PayDateRule {
  final PayDateRuleType type;
  final int? monthlyDay; // nextMonthlyDay
  final int? plusDays; // afterEndPlusDays
  final DateTime? fixedDate; // fixedDate

  const PayDateRule._({
    required this.type,
    this.monthlyDay,
    this.plusDays,
    this.fixedDate,
  });

  const PayDateRule.nextMonthlyDay(int day)
      : this._(type: PayDateRuleType.nextMonthlyDay, monthlyDay: day);

  const PayDateRule.samePeriodEndDay()
      : this._(type: PayDateRuleType.samePeriodEndDay);

  const PayDateRule.afterEndPlusDays(int days)
      : this._(type: PayDateRuleType.afterEndPlusDays, plusDays: days);

  const PayDateRule.fixed(DateTime date)
      : this._(type: PayDateRuleType.fixedDate, fixedDate: date);
}

/// 정산 정책
class PayrollPolicy {
  final PayCycleType cycle;

  /// customDays 전용
  final int? customEveryDays;

  /// 주 시작 요일 (현재는 weekly에서 sunday 고정)
  final WeeklyAnchor? weeklyAnchor;

  /// ✅ 핵심 필드
  /// - weekly: 무시
  /// - twoWeeks: "사용자가 선택한 시작 일요일"
  /// - monthly: 단순 기준점
  final DateTime startFrom;

  /// (레거시) monthlyStartDay – 현재 달력월 고정이라 사용 안 함
  final int? monthlyStartDay;

  /// 지급일 규칙
  final PayDateRule payRule;

  const PayrollPolicy({
    required this.cycle,
    required this.startFrom,
    required this.payRule,
    this.customEveryDays,
    this.weeklyAnchor,
    this.monthlyStartDay,
  });

  PayrollPolicy copyWith({
    PayCycleType? cycle,
    int? customEveryDays,
    WeeklyAnchor? weeklyAnchor,
    DateTime? startFrom,
    int? monthlyStartDay,
    PayDateRule? payRule,
  }) {
    return PayrollPolicy(
      cycle: cycle ?? this.cycle,
      customEveryDays: customEveryDays ?? this.customEveryDays,
      weeklyAnchor: weeklyAnchor ?? this.weeklyAnchor,
      startFrom: startFrom ?? this.startFrom,
      monthlyStartDay: monthlyStartDay ?? this.monthlyStartDay,
      payRule: payRule ?? this.payRule,
    );
  }

  // ─────────────────────────────────────────
  // 프리셋 (UI에서 바로 쓰기 좋게)
  // ─────────────────────────────────────────

  /// 달력월 (1~말일)
  static PayrollPolicy calendarMonth({
    required PayDateRule payRule,
    DateTime? base,
  }) {
    final now = _dateOnly(base ?? DateTime.now());
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: now,
      monthlyStartDay: 1,
      payRule: payRule,
    );
  }

  /// 1주 (일요일 시작 고정)
  static PayrollPolicy weeklySunday({
    required PayDateRule payRule,
    DateTime? base,
  }) {
    final now = _dateOnly(base ?? DateTime.now());
    return PayrollPolicy(
      cycle: PayCycleType.weekly,
      startFrom: now,
      weeklyAnchor: WeeklyAnchor.sunday,
      payRule: payRule,
    );
  }

  /// 2주 (사용자가 선택한 "시작 일요일")
  static PayrollPolicy twoWeeksSunday({
    required DateTime startSunday,
    required PayDateRule payRule,
  }) {
    return PayrollPolicy(
      cycle: PayCycleType.twoWeeks,
      startFrom: _weekStartSunday(startSunday),
      weeklyAnchor: WeeklyAnchor.sunday,
      payRule: payRule,
    );
  }

  /// 단기(당일)
  static PayrollPolicy daily({
    required PayDateRule payRule,
    DateTime? base,
  }) {
    final now = _dateOnly(base ?? DateTime.now());
    return PayrollPolicy(
      cycle: PayCycleType.daily,
      startFrom: now,
      payRule: payRule,
    );
  }
}

/* ─────────────────────────────────────────
   Preview 모델
───────────────────────────────────────── */

class PayPeriod {
  final DateTime start;
  final DateTime end;
  const PayPeriod({required this.start, required this.end});
}

class PeriodPayPreview {
  final PayPeriod period;
  final DateTime payDate;
  const PeriodPayPreview({required this.period, required this.payDate});
}

/// 특정 날짜가 속한 정산 기간 + 지급일 계산
PeriodPayPreview computePreviewForDate({
  required PayrollPolicy policy,
  required DateTime anyDateInPeriod,
}) {
  final d0 = _dateOnly(anyDateInPeriod);
  final anchor = _dateOnly(policy.startFrom);

  late PayPeriod period;

  switch (policy.cycle) {
    case PayCycleType.daily:
      period = PayPeriod(start: d0, end: d0);
      break;

    case PayCycleType.weekly:
      period = _weeklySunday(d0);
      break;

    case PayCycleType.twoWeeks:
      period = _twoWeeksFromAnchor(d0, anchor);
      break;

    case PayCycleType.monthly:
      final startDay = policy.monthlyStartDay;
      if (startDay != null && startDay > 1) {
        period = _anchorMonth(d0, startDay);
      } else {
        period = _calendarMonth(d0);
      }
      break;

    case PayCycleType.customDays:
      final n = (policy.customEveryDays ?? 14).clamp(1, 365);
      period = _nDays(d0, anchor, n);
      break;
  }

  final payDate = _computePayDate(policy.payRule, period);
  return PeriodPayPreview(period: period, payDate: payDate);
}

/* ─────────────────────────────────────────
   helpers
───────────────────────────────────────── */

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _weekStartSunday(DateTime d) {
  final x = _dateOnly(d);
  final offset = x.weekday % 7; // sunday -> 0
  return x.subtract(Duration(days: offset));
}

PayPeriod _weeklySunday(DateTime d) {
  final s = _weekStartSunday(d);
  return PayPeriod(start: s, end: s.add(const Duration(days: 6)));
}

PayPeriod _twoWeeksFromAnchor(DateTime d, DateTime anchor) {
  final s0 = _weekStartSunday(anchor);
  final ws = _weekStartSunday(d);

  if (ws.isBefore(s0)) {
    return PayPeriod(start: s0, end: s0.add(const Duration(days: 13)));
  }

  final diff = ws.difference(s0).inDays;
  final k = diff ~/ 14;
  final start = s0.add(Duration(days: k * 14));
  return PayPeriod(start: start, end: start.add(const Duration(days: 13)));
}

PayPeriod _anchorMonth(DateTime d, int startDay) {
  if (d.day >= startDay) {
    final start = DateTime(d.year, d.month, startDay);
    final nm = d.month == 12 ? 1 : d.month + 1;
    final ny = d.month == 12 ? d.year + 1 : d.year;
    final end = DateTime(ny, nm, startDay).subtract(const Duration(days: 1));
    return PayPeriod(start: start, end: end);
  } else {
    final pm = d.month == 1 ? 12 : d.month - 1;
    final py = d.month == 1 ? d.year - 1 : d.year;
    final start = DateTime(py, pm, startDay);
    final end = DateTime(d.year, d.month, startDay).subtract(const Duration(days: 1));
    return PayPeriod(start: start, end: end);
  }
}

PayPeriod _calendarMonth(DateTime d) {
  final start = DateTime(d.year, d.month, 1);
  final next = (d.month == 12)
      ? DateTime(d.year + 1, 1, 1)
      : DateTime(d.year, d.month + 1, 1);
  return PayPeriod(start: start, end: next.subtract(const Duration(days: 1)));
}

PayPeriod _nDays(DateTime d, DateTime anchor, int n) {
  final a = _dateOnly(anchor);
  if (d.isBefore(a)) {
    return PayPeriod(start: a, end: a.add(Duration(days: n - 1)));
  }
  final diff = d.difference(a).inDays;
  final k = diff ~/ n;
  final start = a.add(Duration(days: k * n));
  return PayPeriod(start: start, end: start.add(Duration(days: n - 1)));
}

DateTime _computePayDate(PayDateRule rule, PayPeriod period) {
  switch (rule.type) {
    case PayDateRuleType.samePeriodEndDay:
      return _dateOnly(period.end);

    case PayDateRuleType.afterEndPlusDays:
      return _dateOnly(period.end).add(Duration(days: rule.plusDays ?? 0));

    case PayDateRuleType.fixedDate:
      return _dateOnly(rule.fixedDate ?? period.end);

    case PayDateRuleType.nextMonthlyDay:
      return _nextMonthlyDay(period.end, rule.monthlyDay ?? 10);
  }
}

DateTime _nextMonthlyDay(DateTime end, int day) {
  final seed = _dateOnly(end).add(const Duration(days: 1));

  int dim(int y, int m) => DateTime(y, m + 1, 0).day;

  DateTime make(int y, int m) {
    final d = day.clamp(1, dim(y, m));
    return DateTime(y, m, d);
  }

  var c = make(seed.year, seed.month);
  if (seed.isAfter(c)) {
    c = make(
      seed.month == 12 ? seed.year + 1 : seed.year,
      seed.month == 12 ? 1 : seed.month + 1,
    );
  }
  return c;
}

/// UI 예시 문장 1줄
String buildPayrollExample(PayrollPolicy policy, DateTime base) {
  final p = computePreviewForDate(policy: policy, anyDateInPeriod: base);
  String f(DateTime d) => '${d.month}/${d.day}';
  return '${f(p.period.start)}~${f(p.period.end)} 근무 → ${f(p.payDate)} 지급';
}
