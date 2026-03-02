// lib/models/store.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../payroll/payroll.dart';
import '../policies/policies.dart' as pol;
import '../policies/policy_mapper.dart' as pm;
import '../payroll/payroll_policy_mapper.dart' show payrollPolicyFromMap;
import 'policy_history.dart';

class Store {
  final String id;
  final String ownerUid;
  final String name;

  /// 서버타임스탬프가 아직 안 찍힌 순간 null일 수 있음
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? colorHex;
  final int? defaultHourlyWage;
  final int? payDay;

  /// ✅ 초대 코드
  final String? storeCode;

  /// ✅ Firestore의 policy 맵 (tax/insurance/surcharge/payrollPolicy 등)
  final Map<String, dynamic>? policy;

  /// ✅ 정책 변경 이력 (날짜별 가산정책 계산용)
  final PolicyHistory policyHistory;

  const Store({
    required this.id,
    required this.ownerUid,
    required this.name,
    this.createdAt,
    this.updatedAt,
    this.colorHex,
    this.defaultHourlyWage,
    this.payDay,
    this.storeCode,
    this.policy,
    this.policyHistory = const PolicyHistory.empty_(),
  });

  // ─────────────────────────────────────────────
  // enabled 스키마 대응 (레거시 혼용)
  // ─────────────────────────────────────────────

  bool get taxEnabled => _enabledOf(policy?['tax']);
  bool get insuranceEnabled => _enabledOf(policy?['insurance']);
  bool get surchargeEnabled => _enabledOf(policy?['surcharge']);

  static bool _enabledOf(dynamic node) {
    if (node == null) return false;

    // wrapper: {enabled: bool, value: ...}
    if (node is Map) {
      final m = node.cast<String, dynamic>();
      if (m.containsKey('enabled')) return m['enabled'] == true;

      // 레거시: enabled가 없으면 "값이 있으면 ON"으로 취급
      if (m.containsKey('value')) return m['value'] != null;
      if (m.containsKey('kind') ||
          m.containsKey('type') ||
          m.containsKey('percent')) {
        return true;
      }
      // surcharge 같은 경우: 필드가 하나라도 있으면 ON 취급(정책 자체가 존재)
      if (m.isNotEmpty) return true;
      return false;
    }

    // 레거시: 문자열로만 저장된 경우 ON
    if (node is String) {
      final s = node.trim().toLowerCase();
      return s.isNotEmpty && s != 'none' && s != 'off' && s != 'false';
    }

    return false;
  }

  // ─────────────────────────────────────────────
  // PayrollPolicy
  // ─────────────────────────────────────────────

  /// ✅ Store에 저장된 payrollPolicy
  /// - policy['payrollPolicy']가 없거나 깨져있으면 "payDay 기반 fallback"을 반환
  ///
  /// ⚠️ 주의(너의 방향성 반영):
  /// - 앞으로 UI에서 payrollPolicy를 "필수 설정"으로 강제할 예정이므로,
  ///   이 fallback은 레거시 데이터/마이그레이션 안전장치 역할만 한다.
  PayrollPolicy get payrollPolicy {
    final raw = policy?['payrollPolicy'];
    if (raw is Map) {
      final parsed = payrollPolicyFromMap(raw.cast<String, dynamic>());
      // payrollPolicyFromMap은 내부 기본값도 안전하게 반환하도록 구성되어 있음
      return parsed;
    }
    return _fallbackPayrollPolicy(payDay);
  }

  /// ✅ tax/insurance/surcharge 값 파싱
  pol.TaxConfig get taxConfig => pm.taxConfigFromPolicy(policy);
  pol.InsuranceConfig get insuranceConfig =>
      pm.insuranceConfigFromPolicy(policy);
  pol.SurchargePolicy get surchargePolicy =>
      pm.surchargePolicyFromPolicy(policy);

  factory Store.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime? _toDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) {
        // 레거시/수동 저장 방어
        return DateTime.tryParse(v);
      }
      if (v is num) {
        // 혹시 epoch(ms)로 들어온 레거시 방어
        final ms = v.toInt();
        if (ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      return null;
    }

    return Store(
      id: doc.id,
      ownerUid: (data['ownerUid'] ?? '') as String,
      name: (data['name'] ?? '') as String,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      colorHex: data['colorHex'] as String?,
      defaultHourlyWage: (data['defaultHourlyWage'] as num?)?.toInt(),
      payDay: (data['payDay'] as num?)?.toInt(),
      storeCode: data['storeCode'] as String?,
      policy: (data['policy'] as Map?)?.cast<String, dynamic>(),
      policyHistory: PolicyHistory.fromList(data['policyHistory']),
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'name': name,
        if (colorHex != null) 'colorHex': colorHex,
        if (defaultHourlyWage != null) 'defaultHourlyWage': defaultHourlyWage,
        if (payDay != null) 'payDay': payDay,
        if (storeCode != null) 'storeCode': storeCode,
        if (policy != null) 'policy': policy,
        // ✅ 정책 이력 저장 (매장 기본 시급 날짜 기반 계산의 핵심)
        if (policyHistory.isNotEmpty)
          'policyHistory':
              policyHistory.entries.map((e) => e.toFirestoreEntry()).toList(),
      };

  Store copyWith({
    String? id,
    String? ownerUid,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? colorHex,
    int? defaultHourlyWage,
    int? payDay,
    String? storeCode,
    Map<String, dynamic>? policy,
    PolicyHistory? policyHistory,
  }) {
    return Store(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      colorHex: colorHex ?? this.colorHex,
      defaultHourlyWage: defaultHourlyWage ?? this.defaultHourlyWage,
      payDay: payDay ?? this.payDay,
      storeCode: storeCode ?? this.storeCode,
      policy: policy ?? this.policy,
      policyHistory: policyHistory ?? this.policyHistory,
    );
  }
}

/// policy['payrollPolicy']가 없을 때 기본값(레거시 안전장치)
PayrollPolicy _fallbackPayrollPolicy(int? payDay) {
  final now = DateTime.now();
  final pd = (payDay ?? 25).clamp(1, 31);

  // ✅ 기본: "달력월 정산 + 다음달 pd일 지급"
  // (앵커일/앵커월 제거한 방향 반영)
  return PayrollPolicy(
    cycle: PayCycleType.monthly,
    startFrom: DateTime(now.year, now.month, now.day),
    payRule: PayDateRule.nextMonthlyDay(pd),
    // monthlyStartDay는 이제 사용 안 하므로 넣지 않음
  );
}
