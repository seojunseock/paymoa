// lib/payroll/payroll_policy_mapper.dart
import 'payroll_policy.dart';

const int kPayrollPolicyVersion = 1;

Map<String, dynamic> payrollPolicyToMap(PayrollPolicy p) {
  return {
    'version': kPayrollPolicyVersion,
    'cycle': p.cycle.name,
    'customEveryDays': p.customEveryDays,
    'weeklyAnchor': p.weeklyAnchor?.name,

    // ✅ dateOnly로 저장(시간/타임존 섞임 방지)
    'startFrom': DateTime(p.startFrom.year, p.startFrom.month, p.startFrom.day)
        .toIso8601String(),

    'monthlyStartDay': p.monthlyStartDay,
    'payRule': payDateRuleToMap(p.payRule),
  };
}

PayrollPolicy payrollPolicyFromMap(Map<String, dynamic>? m) {
  // ✅ 안전 기본값: 달력월(1~말일) + 다음달 10일 지급
  PayrollPolicy _default() {
    final now = _dateOnly(DateTime.now());
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: now,
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(10),
    );
  }

  if (m == null) return _default();

  // version (미래 대비: 지금은 참고만)
  final _ = _toInt(m['version']) ?? 0;

  final cycleStr = (m['cycle'] as String?) ?? PayCycleType.monthly.name;
  final cycle = PayCycleType.values.firstWhere(
    (e) => e.name == cycleStr,
    orElse: () => PayCycleType.monthly,
  );

  final weeklyAnchorStr = m['weeklyAnchor'] as String?;
  final weeklyAnchor = weeklyAnchorStr == null
      ? null
      : WeeklyAnchor.values.firstWhere(
          (e) => e.name == weeklyAnchorStr,
          orElse: () => WeeklyAnchor.monday,
        );

  final customEveryDays = _toInt(m['customEveryDays']);
  final monthlyStartDay = _toInt(m['monthlyStartDay']);

  // ✅ startFrom은 무조건 DateTime(널 불가)로 보정해서 넣기
  final startFrom = _sanitizeStartFrom(_toDateTime(m['startFrom']));

  final payRuleMap = (m['payRule'] as Map?)?.cast<String, dynamic>();
  final payRule = payDateRuleFromMap(payRuleMap);

  return PayrollPolicy(
    cycle: cycle,
    startFrom: startFrom,
    payRule: payRule,
    customEveryDays: customEveryDays,
    weeklyAnchor: weeklyAnchor,
    monthlyStartDay: monthlyStartDay,
  );
}

Map<String, dynamic> payDateRuleToMap(PayDateRule r) {
  return {
    'type': r.type.name,
    'monthlyDay': r.monthlyDay,
    'plusDays': r.plusDays,

    // ✅ dateOnly 저장 권장
    'fixedDate': r.fixedDate == null
        ? null
        : DateTime(r.fixedDate!.year, r.fixedDate!.month, r.fixedDate!.day)
            .toIso8601String(),
  };
}

PayDateRule payDateRuleFromMap(Map<String, dynamic>? m) {
  // ✅ 기본 지급일: 다음달 10일
  if (m == null) return const PayDateRule.nextMonthlyDay(10);

  final typeStr = (m['type'] as String?) ?? PayDateRuleType.nextMonthlyDay.name;
  final type = PayDateRuleType.values.firstWhere(
    (e) => e.name == typeStr,
    orElse: () => PayDateRuleType.nextMonthlyDay,
  );

  switch (type) {
    case PayDateRuleType.samePeriodEndDay:
      return const PayDateRule.samePeriodEndDay();

    case PayDateRuleType.afterEndPlusDays:
      final n = (_toInt(m['plusDays']) ?? 0).clamp(0, 365);
      return PayDateRule.afterEndPlusDays(n);

    case PayDateRuleType.fixedDate:
      final dt = _toDateTime(m['fixedDate']);
      // ✅ fixedDate도 안전 보정
      return PayDateRule.fixed(_sanitizeStartFrom(dt));

    case PayDateRuleType.nextMonthlyDay:
      final day = (_toInt(m['monthlyDay']) ?? 10).clamp(1, 31);
      return PayDateRule.nextMonthlyDay(day);
  }
}

int? _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// ✅ “무조건 DateTime 반환(널 불가)”
/// - 너무 과거/미래는 오늘로 보정
DateTime _sanitizeStartFrom(DateTime? d) {
  final now = _dateOnly(DateTime.now());
  if (d == null) return now;

  final dd = _dateOnly(d);

  // 이상치 방어 (파싱 오류/레거시 데이터 대비)
  if (dd.year < 2000 || dd.year > 2100) return now;

  return dd;
}
