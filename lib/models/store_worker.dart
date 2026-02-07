// lib/models/store_worker.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../policies/policies.dart' as pol;
import '../policies/policy_mapper.dart' as pm;
import 'store.dart';

class StoreWorker {
  final String workerUid;
  final String? displayName;

  /// ✅ 매장 기본값 상속 여부
  final bool inheritFromStore;

  /// ✅ 개별 설정 (없을 수 있음)
  final int? hourlyWage;
  final int? payDay;

  /// ✅ 개별 정책 오버라이드 (policy_mapper 포맷 권장)
  final Map<String, dynamic>? policyOverride;

  /// ✅ 드래그 정렬용
  final int sortIndex;

  /// ✅ 상태 관리: 'active' | 'ended'
  final String status;

  final DateTime? joinedAt;
  final DateTime? updatedAt;
  final DateTime? endedAt;

  const StoreWorker({
    required this.workerUid,
    this.displayName,
    required this.inheritFromStore,
    this.hourlyWage,
    this.payDay,
    this.policyOverride,
    this.sortIndex = 0,
    this.status = 'active',
    this.joinedAt,
    this.updatedAt,
    this.endedAt,
  });

  bool get isActive => status != 'ended';

  // ─────────────────────────────
  // ✅ "실제 적용값" 계산 헬퍼들 (장기 안정)
  // ─────────────────────────────

  int effectiveHourlyWage(Store store) {
    final storeWage = store.defaultHourlyWage ?? 0;
    if (inheritFromStore) return storeWage;
    return hourlyWage ?? storeWage;
  }

  int effectivePayDay(Store store) {
    final storePayDay = (store.payDay ?? 25).clamp(1, 31);
    if (inheritFromStore) return storePayDay;
    return (payDay ?? storePayDay).clamp(1, 31);
  }

  /// ✅ 세금도 “상속 OFF”면 override 적용 가능하게 (필요 없으면 안 써도 됨)
  pol.TaxConfig effectiveTax(Store store) {
    if (inheritFromStore) return store.taxConfig;
    final po = policyOverride ?? const <String, dynamic>{};
    return pm.taxConfigFromPolicy(po);
  }

  /// ✅ 보험도 “상속 OFF”면 override 적용 가능하게 (필요 없으면 안 써도 됨)
  pol.InsuranceConfig effectiveInsurance(Store store) {
    if (inheritFromStore) return store.insuranceConfig;
    final po = policyOverride ?? const <String, dynamic>{};
    return pm.insuranceConfigFromPolicy(po);
  }

  /// ✅ 핵심: surcharge는 enabled 포맷을 반드시 존중해야 함
  pol.SurchargePolicy effectiveSurchargePolicy(Store store) {
    if (inheritFromStore) return store.surchargePolicy;

    final po = policyOverride ?? const <String, dynamic>{};
    return pm.surchargePolicyFromPolicy(po);
  }

  String displayLabel() {
    final dn = (displayName ?? '').trim();
    return dn.isEmpty ? workerUid : dn;
  }

  // ─────────────────────────────
  // JSON / Firestore helpers
  // ─────────────────────────────

  static DateTime? _dt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static int _toInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  factory StoreWorker.fromJson(Map<String, dynamic> json, {String? docId}) {
    final uidRaw = (json['workerUid'] as String?)?.trim();
    final uid = (uidRaw != null && uidRaw.isNotEmpty) ? uidRaw : (docId ?? '');

    return StoreWorker(
      workerUid: uid,
      displayName: (json['displayName'] as String?)?.trim(),
      inheritFromStore: (json['inheritFromStore'] as bool?) ?? true,
      hourlyWage: (json['hourlyWage'] as num?)?.toInt(),
      payDay: (json['payDay'] as num?)?.toInt(),
      policyOverride: (json['policyOverride'] as Map?)?.cast<String, dynamic>(),
      sortIndex: _toInt(json['sortIndex'], fallback: 0),
      status: (json['status'] as String?) ?? 'active',
      joinedAt: _dt(json['joinedAt']),
      updatedAt: _dt(json['updatedAt']),
      endedAt: _dt(json['endedAt']),
    );
  }

  /// ✅ QueryDocumentSnapshot 버전
  static StoreWorker fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return StoreWorker.fromJson(doc.data(), docId: doc.id);
  }

  /// ✅ DocumentSnapshot 버전
  static StoreWorker? fromSnap(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return StoreWorker.fromJson(data, docId: doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'workerUid': workerUid,
      if (displayName != null) 'displayName': displayName,
      'inheritFromStore': inheritFromStore,
      if (hourlyWage != null) 'hourlyWage': hourlyWage,
      if (payDay != null) 'payDay': payDay,
      if (policyOverride != null) 'policyOverride': policyOverride,
      'sortIndex': sortIndex,
      'status': status,
      if (joinedAt != null) 'joinedAt': Timestamp.fromDate(joinedAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
    };
  }

  StoreWorker copyWith({
    String? workerUid,
    String? displayName,
    bool? inheritFromStore,
    int? hourlyWage,
    int? payDay,
    Map<String, dynamic>? policyOverride,
    int? sortIndex,
    String? status,
    DateTime? joinedAt,
    DateTime? updatedAt,
    DateTime? endedAt,
  }) {
    return StoreWorker(
      workerUid: workerUid ?? this.workerUid,
      displayName: displayName ?? this.displayName,
      inheritFromStore: inheritFromStore ?? this.inheritFromStore,
      hourlyWage: hourlyWage ?? this.hourlyWage,
      payDay: payDay ?? this.payDay,
      policyOverride: policyOverride ?? this.policyOverride,
      sortIndex: sortIndex ?? this.sortIndex,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}
