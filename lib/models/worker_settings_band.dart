import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerSettingsBand {
  /// 예: 20260126
  final int effectiveFromYmd;

  final String ownerUid;
  final String storeId;
  final String workerUid;

  final bool inheritFromStore;

  /// 개별 설정일 때만 의미
  final int? hourlyWage;
  final int? payDay;
  final Map<String, dynamic>? policyOverride;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkerSettingsBand({
    required this.effectiveFromYmd,
    required this.ownerUid,
    required this.storeId,
    required this.workerUid,
    required this.inheritFromStore,
    this.hourlyWage,
    this.payDay,
    this.policyOverride,
    this.createdAt,
    this.updatedAt,
  });

  static int ymdInt(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  factory WorkerSettingsBand.fromJson(Map<String, dynamic> m) {
    return WorkerSettingsBand(
      effectiveFromYmd: (m['effectiveFromYmd'] as num?)?.toInt() ?? 19700101,
      ownerUid: (m['ownerUid'] as String?) ?? '',
      storeId: (m['storeId'] as String?) ?? '',
      workerUid: (m['workerUid'] as String?) ?? '',
      inheritFromStore: (m['inheritFromStore'] as bool?) ?? true,
      hourlyWage: (m['hourlyWage'] as num?)?.toInt(),
      payDay: (m['payDay'] as num?)?.toInt(),
      policyOverride: (m['policyOverride'] as Map?)?.cast<String, dynamic>(),
      createdAt: _toDate(m['createdAt']),
      updatedAt: _toDate(m['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'effectiveFromYmd': effectiveFromYmd,
      'ownerUid': ownerUid,
      'storeId': storeId,
      'workerUid': workerUid,
      'inheritFromStore': inheritFromStore,
      if (hourlyWage != null) 'hourlyWage': hourlyWage,
      if (payDay != null) 'payDay': payDay,
      if (policyOverride != null) 'policyOverride': policyOverride,
    };
  }
}

/// ✅ 특정 날짜(ymd)에 유효한 band 찾기
WorkerSettingsBand? resolveBandForYmd(
  List<WorkerSettingsBand> bands,
  int ymd,
) {
  if (bands.isEmpty) return null;

  // bands는 effectiveFromYmd 오름차순 가정
  WorkerSettingsBand? last;
  for (final b in bands) {
    if (b.effectiveFromYmd <= ymd) {
      last = b;
    } else {
      break;
    }
  }
  return last;
}
