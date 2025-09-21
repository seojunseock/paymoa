// lib/policies/policies.dart
// 정책 타입들을 한 곳에서 정의합니다. (parseColor는 여기서 제공하지 않습니다)

/// ---- Tax ----
sealed class TaxConfig {
  const TaxConfig();
  static const none  = _TaxFixed._('none');
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
  bool operator ==(Object other) => other is TaxConfigCustomPercent && other.percent == percent;
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
class SurchargePolicy {
  final bool weeklyHolidayEnabled;

  final bool overtimeEnabled;
  final int  overtimePercent;

  final bool holidayEnabled;
  final int  holidayPercent;

  final bool nightEnabled;
  final int  nightPercent;

  const SurchargePolicy({
    this.weeklyHolidayEnabled = false,
    this.overtimeEnabled = false,
    this.overtimePercent = 0,
    this.holidayEnabled = false,
    this.holidayPercent = 0,
    this.nightEnabled = false,
    this.nightPercent = 0,
  });

  SurchargePolicy copyWith({
    bool? weeklyHolidayEnabled,
    bool? overtimeEnabled,
    int?  overtimePercent,
    bool? holidayEnabled,
    int?  holidayPercent,
    bool? nightEnabled,
    int?  nightPercent,
  }) {
    return SurchargePolicy(
      weeklyHolidayEnabled: weeklyHolidayEnabled ?? this.weeklyHolidayEnabled,
      overtimeEnabled: overtimeEnabled ?? this.overtimeEnabled,
      overtimePercent: overtimePercent ?? this.overtimePercent,
      holidayEnabled: holidayEnabled ?? this.holidayEnabled,
      holidayPercent: holidayPercent ?? this.holidayPercent,
      nightEnabled: nightEnabled ?? this.nightEnabled,
      nightPercent: nightPercent ?? this.nightPercent,
    );
  }
}
