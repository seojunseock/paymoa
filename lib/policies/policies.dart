// lib/policies/policies.dart
// 정책 타입들을 한 곳에서 정의합니다. (parseColor는 여기서 제공하지 않습니다)

/// ---- Tax ----
sealed class TaxConfig {
  const TaxConfig();
  static const none = _TaxFixed._('none');
  static const biz33 = _TaxFixed._('biz33');
  static const day66 = _TaxFixed._('day66');
}

class _TaxFixed extends TaxConfig {
  final String kind;
  const _TaxFixed._(this.kind);

  @override
  int get hashCode => kind.hashCode;

  @override
  bool operator ==(Object other) => other is _TaxFixed && other.kind == kind;
}

/// 커스텀 퍼센트(예: 5.0%)
class TaxConfigCustomPercent extends TaxConfig {
  final double percent;
  const TaxConfigCustomPercent(this.percent);

  @override
  int get hashCode => percent.hashCode;

  @override
  bool operator ==(Object other) =>
      other is TaxConfigCustomPercent && other.percent == percent;
}

/// ---- Insurance ----
sealed class InsuranceConfig {
  const InsuranceConfig();
}

class InsuranceNone extends InsuranceConfig {
  const InsuranceNone();
}

class InsuranceEmploymentOnly extends InsuranceConfig {
  const InsuranceEmploymentOnly();
}

class InsuranceFour extends InsuranceConfig {
  const InsuranceFour();
}

/// ---- Surcharge ----
/// percent는 정수(50, 100, 150 …)
///
/// ✅ 방향성(“강요 없음, 사장님이 선택”)
/// - 휴일 정의: (1) 매장 주휴일(기본: 일요일) + (2) 추가휴일(ymd 문자열 목록)
/// - 휴일근로 가산: 한국식 "8시간 이내/초과" 2단계(옵션)
/// - 주휴수당: 기본 8시간 고정(옵션) vs "주 평균 1일 소정근로시간" 근사(옵션)
enum OvertimeRule {
  /// MVP: 1일 8시간 초과분만 연장으로 간주 (현재 방식)
  dailyOver8,

  /// 고급: 주 40시간 초과분 기준(추후 확장)
  weeklyOver40,
}

class SurchargePolicy {
  // ── 주휴수당 ─────────────────────────
  final bool weeklyHolidayEnabled;

  /// ✅ 주휴일 요일(1=월 ... 7=일). 기본: 일요일
  final int weeklyHolidayWeekday;

  /// ✅ 주휴수당 시간 계산 방식
  /// - true : fixedMinutes(기본 480=8시간)로 지급
  /// - false: 그 주 실제 근로일수로 나눈 "평균 1일 근로시간" 근사
  final bool weeklyHolidayUseFixedMinutes;
  final int weeklyHolidayFixedMinutes; // 기본 480

  // ── 연장/야간/휴일 가산 ──────────────
  final bool overtimeEnabled;
  final int overtimePercent;
  final OvertimeRule overtimeRule;

  final bool holidayEnabled;
  final int holidayPercent;

  /// ✅ “한국식 휴일근로 2단계(8시간 이내/초과)” 적용 옵션
  /// - true  : 휴일근로 8시간 이내 = holidayPercent
  ///          휴일근로 8시간 초과 = max(holidayPercent, 100)
  /// - false : 휴일근로 전 구간 = holidayPercent
  final bool holidayUseKoreanLawTier;

  /// ✅ 추가 휴일(약정휴일/공휴일 등): "YYYY-MM-DD"
  /// - 공휴일 자동 캘린더는 나중에(서버/패키지) 붙이고,
  ///   MVP는 사장님이 직접 추가 등록하는 방식으로도 충분히 실무 대응 가능.
  final List<String> extraHolidayYmds;

  final bool nightEnabled;
  final int nightPercent;

  const SurchargePolicy({
    // weekly holiday
    this.weeklyHolidayEnabled = false,
    this.weeklyHolidayWeekday = DateTime.sunday,
    this.weeklyHolidayUseFixedMinutes = true,
    this.weeklyHolidayFixedMinutes = 8 * 60,

    // overtime
    this.overtimeEnabled = false,
    this.overtimePercent = 0,
    this.overtimeRule = OvertimeRule.dailyOver8,

    // holiday
    this.holidayEnabled = false,
    this.holidayPercent = 0,
    this.holidayUseKoreanLawTier = false,
    this.extraHolidayYmds = const <String>[],

    // night
    this.nightEnabled = false,
    this.nightPercent = 0,
  });

  SurchargePolicy copyWith({
    bool? weeklyHolidayEnabled,
    int? weeklyHolidayWeekday,
    bool? weeklyHolidayUseFixedMinutes,
    int? weeklyHolidayFixedMinutes,
    bool? overtimeEnabled,
    int? overtimePercent,
    OvertimeRule? overtimeRule,
    bool? holidayEnabled,
    int? holidayPercent,
    bool? holidayUseKoreanLawTier,
    List<String>? extraHolidayYmds,
    bool? nightEnabled,
    int? nightPercent,
  }) {
    return SurchargePolicy(
      weeklyHolidayEnabled: weeklyHolidayEnabled ?? this.weeklyHolidayEnabled,
      weeklyHolidayWeekday: weeklyHolidayWeekday ?? this.weeklyHolidayWeekday,
      weeklyHolidayUseFixedMinutes:
          weeklyHolidayUseFixedMinutes ?? this.weeklyHolidayUseFixedMinutes,
      weeklyHolidayFixedMinutes:
          weeklyHolidayFixedMinutes ?? this.weeklyHolidayFixedMinutes,
      overtimeEnabled: overtimeEnabled ?? this.overtimeEnabled,
      overtimePercent: overtimePercent ?? this.overtimePercent,
      overtimeRule: overtimeRule ?? this.overtimeRule,
      holidayEnabled: holidayEnabled ?? this.holidayEnabled,
      holidayPercent: holidayPercent ?? this.holidayPercent,
      holidayUseKoreanLawTier:
          holidayUseKoreanLawTier ?? this.holidayUseKoreanLawTier,
      extraHolidayYmds: extraHolidayYmds ?? this.extraHolidayYmds,
      nightEnabled: nightEnabled ?? this.nightEnabled,
      nightPercent: nightPercent ?? this.nightPercent,
    );
  }
}
