// lib/policies/policy_mapper.dart
import 'policies.dart' as pol;
import '../payroll/payroll.dart';
import '../payroll/payroll_policy_mapper.dart' as ppm;

/// Firestore policy(Map) <-> 정책 객체 변환 유틸 (장기 안정 버전)
///
/// ✅ 읽기(fromPolicy): 레거시/신규 혼재 허용
/// ✅ 저장(toPolicy): enabled wrapper 형태로 통일
///
/// 핵심 포인트:
/// - surcharge는 enabled가 "없는" 레거시도 정책 필드가 있으면 ON으로 판단
/// - surcharge 파싱 범위를 정책 전체 필드로 확장(weekday/fixedMinutes/overtimeRule/extraHolidayYmds 등)
/// - ✅ (추가) surcharge도 { value: ... } wrapper 형태 대응

/* ─────────────────────────────────────────────
   ✅ FROM (Firestore -> App)
───────────────────────────────────────────── */

pol.TaxConfig taxConfigFromPolicy(Map<String, dynamic>? policy) {
  final raw = policy?['tax'];
  return taxConfigFromAny(raw);
}

pol.TaxConfig taxConfigFromAny(dynamic raw) {
  if (raw == null) return pol.TaxConfig.none;

  // wrapper: {enabled, value}
  if (raw is Map) {
    final m = raw.cast<String, dynamic>();

    // enabled가 명시된 경우만 OFF로 판단
    if (m.containsKey('enabled')) {
      final enabled = _toBool(m['enabled']);
      if (enabled == false) return pol.TaxConfig.none;
    }

    // value 래핑
    if (m.containsKey('value')) {
      return taxConfigFromAny(m['value']);
    }

    final kind = (m['kind'] as String?) ?? (m['type'] as String?) ?? '';

    if (kind == 'customPercent' || kind == 'custom' || kind == 'percent') {
      final pct = _toDouble(m['percent']) ?? 0.0;
      return pol.TaxConfigCustomPercent(pct);
    }

    switch (kind) {
      case 'none':
        return pol.TaxConfig.none;
      case 'biz33':
        return pol.TaxConfig.biz33;
      case 'day66':
        return pol.TaxConfig.day66;
    }

    // 혹시 percent만 덜렁 있는 레거시
    if (m.containsKey('percent')) {
      final pct = _toDouble(m['percent']);
      if (pct != null) return pol.TaxConfigCustomPercent(pct);
    }

    return pol.TaxConfig.none;
  }

  if (raw is String) {
    switch (raw.trim()) {
      case 'none':
        return pol.TaxConfig.none;
      case 'biz33':
        return pol.TaxConfig.biz33;
      case 'day66':
        return pol.TaxConfig.day66;
      default:
        return pol.TaxConfig.none;
    }
  }

  return pol.TaxConfig.none;
}

pol.InsuranceConfig insuranceConfigFromPolicy(Map<String, dynamic>? policy) {
  final raw = policy?['insurance'];
  return insuranceConfigFromAny(raw);
}

pol.InsuranceConfig insuranceConfigFromAny(dynamic raw) {
  if (raw == null) return const pol.InsuranceNone();

  if (raw is Map) {
    final m = raw.cast<String, dynamic>();

    // enabled가 명시된 경우만 OFF 처리
    if (m.containsKey('enabled')) {
      final enabled = _toBool(m['enabled']);
      if (enabled == false) return const pol.InsuranceNone();
    }

    if (m.containsKey('value')) {
      return insuranceConfigFromAny(m['value']);
    }

    final kind = (m['kind'] as String?) ?? (m['type'] as String?) ?? '';
    switch (kind) {
      case 'none':
        return const pol.InsuranceNone();
      case 'employmentOnly':
        return const pol.InsuranceEmploymentOnly();
      case 'four':
        return const pol.InsuranceFour();
    }

    return const pol.InsuranceNone();
  }

  if (raw is String) {
    switch (raw.trim()) {
      case 'none':
        return const pol.InsuranceNone();
      case 'employmentOnly':
        return const pol.InsuranceEmploymentOnly();
      case 'four':
        return const pol.InsuranceFour();
      default:
        return const pol.InsuranceNone();
    }
  }

  return const pol.InsuranceNone();
}

pol.SurchargePolicy surchargePolicyFromPolicy(Map<String, dynamic>? policy) {
  final raw = policy?['surcharge'];
  return surchargePolicyFromAny(raw);
}

pol.SurchargePolicy surchargePolicyFromAny(dynamic raw) {
  if (raw == null) return const pol.SurchargePolicy();

  if (raw is Map) {
    final m = raw.cast<String, dynamic>();

    // ✅ (추가) value wrapper 대응
    if (m.containsKey('value')) {
      return surchargePolicyFromAny(m['value']);
    }

    // ✅ enabled 없는 레거시 보정:
    // - enabled가 있으면 그 값을 따름
    // - enabled가 없으면 "정책 필드가 하나라도 있으면 ON"으로 판단
    final hasEnabled = m.containsKey('enabled');
    final enabled = hasEnabled
        ? (_toBool(m['enabled']) ?? false)
        : _inferSurchargeEnabledLegacy(m);

    if (!enabled) return const pol.SurchargePolicy();

    // 필드 파싱(없으면 기본값)
    final weeklyHolidayEnabled = _toBool(m['weeklyHolidayEnabled']) ?? false;

    final weeklyHolidayWeekday = _clampInt(
      _toInt(m['weeklyHolidayWeekday']) ?? DateTime.sunday,
      DateTime.monday,
      DateTime.sunday,
    );

    final weeklyHolidayUseFixedMinutes =
        _toBool(m['weeklyHolidayUseFixedMinutes']) ?? false;

    final weeklyHolidayFixedMinutes = _clampInt(
      _toInt(m['weeklyHolidayFixedMinutes']) ?? (8 * 60),
      0,
      24 * 60,
    );

    final overtimeEnabled = _toBool(m['overtimeEnabled']) ?? false;
    final overtimePercent =
        _clampInt(_toInt(m['overtimePercent']) ?? 50, 0, 300);

    final overtimeRuleStr = (m['overtimeRule'] as String?)?.trim();
    final overtimeRule =
        _parseOvertimeRule(overtimeRuleStr) ?? pol.OvertimeRule.dailyOver8;

    final holidayEnabled = _toBool(m['holidayEnabled']) ?? false;
    final holidayPercent = _clampInt(_toInt(m['holidayPercent']) ?? 50, 0, 300);

    final holidayUseKoreanLawTier =
        _toBool(m['holidayUseKoreanLawTier']) ?? false;

    final extraHolidayYmds = _toStringList(m['extraHolidayYmds']);

    final nightEnabled = _toBool(m['nightEnabled']) ?? false;
    final nightPercent = _clampInt(_toInt(m['nightPercent']) ?? 50, 0, 300);

    return pol.SurchargePolicy(
      weeklyHolidayEnabled: weeklyHolidayEnabled,
      weeklyHolidayWeekday: weeklyHolidayWeekday,
      weeklyHolidayUseFixedMinutes: weeklyHolidayUseFixedMinutes,
      weeklyHolidayFixedMinutes: weeklyHolidayFixedMinutes,
      overtimeEnabled: overtimeEnabled,
      overtimePercent: overtimePercent,
      overtimeRule: overtimeRule,
      holidayEnabled: holidayEnabled,
      holidayPercent: holidayPercent,
      holidayUseKoreanLawTier: holidayUseKoreanLawTier,
      extraHolidayYmds: extraHolidayYmds,
      nightEnabled: nightEnabled,
      nightPercent: nightPercent,
    );
  }

  // 문자열/기타 레거시는 안전하게 OFF
  return const pol.SurchargePolicy();
}

/* ─────────────────────────────────────────────
   ✅ TO (App -> Firestore)  저장용
───────────────────────────────────────────── */

Map<String, dynamic> taxConfigToPolicyNode(pol.TaxConfig tax) {
  if (tax == pol.TaxConfig.none) {
    return {'enabled': false, 'kind': 'none', 'value': 'none'};
  }
  if (tax == pol.TaxConfig.biz33) {
    return {'enabled': true, 'kind': 'biz33', 'value': 'biz33'};
  }
  if (tax == pol.TaxConfig.day66) {
    return {'enabled': true, 'kind': 'day66', 'value': 'day66'};
  }

  if (tax is pol.TaxConfigCustomPercent) {
    final pct = _clampDouble(tax.percent, 0.0, 100.0);
    return {
      'enabled': true,
      'kind': 'customPercent',
      'value': {'kind': 'customPercent', 'percent': pct},
    };
  }

  return {'enabled': false, 'kind': 'none', 'value': 'none'};
}

Map<String, dynamic> insuranceConfigToPolicyNode(pol.InsuranceConfig ins) {
  if (ins is pol.InsuranceNone) {
    return {'enabled': false, 'kind': 'none', 'value': 'none'};
  }
  if (ins is pol.InsuranceEmploymentOnly) {
    return {
      'enabled': true,
      'kind': 'employmentOnly',
      'value': 'employmentOnly',
    };
  }
  if (ins is pol.InsuranceFour) {
    return {'enabled': true, 'kind': 'four', 'value': 'four'};
  }
  return {'enabled': false, 'kind': 'none', 'value': 'none'};
}

Map<String, dynamic> surchargePolicyToPolicyNode(pol.SurchargePolicy s) {
  // enabled 기준: ON 항목이 하나라도 있으면 true
  final enabled = s.weeklyHolidayEnabled ||
      s.overtimeEnabled ||
      s.holidayEnabled ||
      s.nightEnabled;

  return {
    'enabled': enabled,

    // weekly holiday
    'weeklyHolidayEnabled': s.weeklyHolidayEnabled,
    'weeklyHolidayWeekday': s.weeklyHolidayWeekday,
    'weeklyHolidayUseFixedMinutes': s.weeklyHolidayUseFixedMinutes,
    'weeklyHolidayFixedMinutes':
        _clampInt(s.weeklyHolidayFixedMinutes, 0, 24 * 60),

    // overtime
    'overtimeEnabled': s.overtimeEnabled,
    'overtimePercent': _clampInt(s.overtimePercent, 0, 300),
    'overtimeRule': s.overtimeRule.name,

    // holiday
    'holidayEnabled': s.holidayEnabled,
    'holidayPercent': _clampInt(s.holidayPercent, 0, 300),
    'holidayUseKoreanLawTier': s.holidayUseKoreanLawTier,
    'extraHolidayYmds': s.extraHolidayYmds,

    // night
    'nightEnabled': s.nightEnabled,
    'nightPercent': _clampInt(s.nightPercent, 0, 300),
  };
}

/// ✅ Store.policy / StoreWorker.policyOverride 만들 때 쓰는 표준 빌더
Map<String, dynamic> buildPolicyMap({
  required pol.TaxConfig tax,
  required pol.InsuranceConfig insurance,
  pol.SurchargePolicy? surcharge,
  PayrollPolicy? payrollPolicy,
}) {
  final out = <String, dynamic>{};
  out['tax'] = taxConfigToPolicyNode(tax);
  out['insurance'] = insuranceConfigToPolicyNode(insurance);

  // surcharge는 null이면 off로 명시
  out['surcharge'] = (surcharge == null)
      ? <String, dynamic>{'enabled': false}
      : surchargePolicyToPolicyNode(surcharge);

  // ✅ payrollPolicy도 함께 저장 (앱 재시작 시 복원)
  if (payrollPolicy != null) {
    out['payrollPolicy'] = ppm.payrollPolicyToMap(payrollPolicy);
  }

  return out;
}

/* ─────────────────────────────────────────────
   helpers (안전)
───────────────────────────────────────────── */

bool _inferSurchargeEnabledLegacy(Map<String, dynamic> m) {
  // enabled가 없던 레거시:
  // - known keys 중 하나라도 존재하면 ON으로 본다.
  const keys = <String>[
    'weeklyHolidayEnabled',
    'weeklyHolidayWeekday',
    'weeklyHolidayUseFixedMinutes',
    'weeklyHolidayFixedMinutes',
    'overtimeEnabled',
    'overtimePercent',
    'overtimeRule',
    'holidayEnabled',
    'holidayPercent',
    'holidayUseKoreanLawTier',
    'extraHolidayYmds',
    'nightEnabled',
    'nightPercent',
  ];

  for (final k in keys) {
    if (m.containsKey(k)) return true;
  }

  // 혹시라도 map이 비어있지 않다면(서버가 다른 키로 저장했을 수도)
  // “정책 존재”로 보고 ON 취급(OFF는 enabled=false로만 표현하도록 유도)
  return m.isNotEmpty;
}

pol.OvertimeRule? _parseOvertimeRule(String? s) {
  if (s == null || s.isEmpty) return null;
  for (final r in pol.OvertimeRule.values) {
    if (r.name == s) return r;
  }
  return null;
}

List<String> _toStringList(dynamic v) {
  if (v == null) return const <String>[];
  if (v is List) {
    return v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return const <String>[];
    // 쉼표 구분 레거시도 대응
    return s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

bool? _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'y' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'n' || s == 'no') return false;
  }
  return null;
}

int? _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _toDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int _clampInt(int v, int min, int max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

double _clampDouble(double v, double min, double max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}
