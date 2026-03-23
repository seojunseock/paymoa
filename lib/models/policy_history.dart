// lib/models/policy_history.dart
//
// 정책 변경 이력 - 날짜별로 어떤 정책이 적용됐는지 추적
// 시급처럼 가산정책(야간%, 휴일%, 주휴, 연장)도 변경 날짜 기준으로 계산

import '../policies/policies.dart';
import '../policies/policy_mapper.dart' as pm;

/// 정책 변경 이력 항목 1개
class PolicyHistoryEntry {
  final DateTime effectiveFrom; // 이 날부터 아래 정책 적용
  final Map<String, dynamic> rawPolicy; // Firestore 저장 형태 그대로

  const PolicyHistoryEntry({
    required this.effectiveFrom,
    required this.rawPolicy,
  });

  SurchargePolicy get surcharge => pm.surchargePolicyFromPolicy(rawPolicy);
  TaxConfig get tax => pm.taxConfigFromPolicy(rawPolicy);
  InsuranceConfig get insurance => pm.insuranceConfigFromPolicy(rawPolicy);

  /// ✅ 이 항목 기준 시급
  int? get hourlyWage {
    final v = rawPolicy['hourlyWage'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  /// ✅ 이 항목 이전(변경 전) 시급
  /// wageAt(date)에서 모든 항목보다 이전 날짜의 fallback으로 사용
  int? get previousHourlyWage {
    final v = rawPolicy['previousHourlyWage'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  /// Firestore 배열 항목 → PolicyHistoryEntry
  static PolicyHistoryEntry? fromMap(dynamic m) {
    if (m is! Map) return null;
    final map = m.cast<String, dynamic>();
    final raw = map['effectiveFrom'];
    if (raw == null) return null;

    DateTime? parsed;

    if (raw is String) {
      final dateStr = raw.trim();
      if (dateStr.isEmpty) return null;
      final parts = dateStr.split('-');
      if (parts.length < 3) return null;
      final y = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || mo == null || d == null) return null;
      parsed = DateTime(y, mo, d);
    } else if (raw is int) {
      final y = raw ~/ 10000;
      final mo = (raw % 10000) ~/ 100;
      final d = raw % 100;
      if (y <= 0 || mo <= 0 || d <= 0) return null;
      parsed = DateTime(y, mo, d);
    } else if (raw is num) {
      final v = raw.toInt();
      final y = v ~/ 10000;
      final mo = (v % 10000) ~/ 100;
      final d = v % 100;
      if (y <= 0 || mo <= 0 || d <= 0) return null;
      parsed = DateTime(y, mo, d);
    } else {
      return null;
    }

    return PolicyHistoryEntry(
      effectiveFrom: parsed,
      rawPolicy: map,
    );
  }

  Map<String, dynamic> toFirestoreEntry() => {
        ...rawPolicy,
        'effectiveFrom': _ymd(effectiveFrom),
      };
}

/// 정책 이력 전체
class PolicyHistory {
  final List<PolicyHistoryEntry> _entries; // 날짜 오름차순 정렬

  const PolicyHistory._(this._entries);

  /// 빈 이력 (factory)
  factory PolicyHistory.empty() => const PolicyHistory._([]);

  /// 빈 이력 (const 생성자 - default parameter용)
  const PolicyHistory.empty_() : _entries = const [];

  static Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> extra,
  ) {
    final out = <String, dynamic>{...base};
    extra.forEach((key, value) {
      if (key == 'effectiveFrom') {
        out[key] = value;
        return;
      }
      if (value is Map &&
          out[key] is Map &&
          value.isNotEmpty &&
          (out[key] as Map).isNotEmpty) {
        out[key] = {
          ...(out[key] as Map).cast<String, dynamic>(),
          ...value.cast<String, dynamic>(),
        };
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  /// Firestore 배열 → PolicyHistory
  factory PolicyHistory.fromList(dynamic list) {
    if (list is! List) return PolicyHistory.empty();

    final byDate = <String, PolicyHistoryEntry>{};
    final order = <String>[];

    for (final item in list) {
      final e = PolicyHistoryEntry.fromMap(item);
      if (e == null) continue;

      final key = _ymd(e.effectiveFrom);
      if (!byDate.containsKey(key)) {
        byDate[key] = e;
        order.add(key);
      } else {
        final prev = byDate[key]!;
        byDate[key] = PolicyHistoryEntry(
          effectiveFrom: prev.effectiveFrom,
          rawPolicy: _mergeMaps(prev.rawPolicy, e.rawPolicy),
        );
      }
    }

    final entries = order.map((k) => byDate[k]!).toList()
      ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));

    return PolicyHistory._(entries);
  }

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  /// [date] 날짜에 적용되는 정책 항목
  /// → 그 날 이전/당일 중 가장 최근 항목 반환
  /// → 없으면 null (계산기에서 기본 policy 사용)
  PolicyHistoryEntry? entryAt(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    PolicyHistoryEntry? result;
    for (final e in _entries) {
      if (!e.effectiveFrom.isAfter(d)) {
        result = e;
      } else {
        break;
      }
    }
    return result;
  }

  /// 편의 함수들
  SurchargePolicy? surchargeAt(DateTime date) => entryAt(date)?.surcharge;
  TaxConfig? taxAt(DateTime date) => entryAt(date)?.tax;
  InsuranceConfig? insuranceAt(DateTime date) => entryAt(date)?.insurance;

  /// ✅ 날짜별 유효 시급
  /// - 해당 날짜에 적용되는 이력 항목의 hourlyWage 반환
  /// - 모든 이력보다 이전 날짜면 가장 첫 항목의 previousHourlyWage 반환
  /// - 없으면 null (호출처에서 alba.hourlyWage로 fallback)
  int? wageAt(DateTime date) {
    if (_entries.isEmpty) return null;
    final d = DateTime(date.year, date.month, date.day);
    PolicyHistoryEntry? found;
    for (final e in _entries) {
      if (!e.effectiveFrom.isAfter(d)) {
        found = e;
      } else {
        break;
      }
    }
    if (found != null) return found.hourlyWage;
    // date가 모든 항목보다 이전 → 첫 항목의 이전 시급 반환
    return _entries.first.previousHourlyWage;
  }

  /// 새 항목 Firestore 저장용 맵 생성
  static Map<String, dynamic> buildEntry({
    required DateTime effectiveFrom,
    required Map<String, dynamic> policyMap,
  }) {
    return {
      ...policyMap,
      'effectiveFrom': _ymd(effectiveFrom),
    };
  }

  /// ✅ 새 항목 추가 (메모리 즉시 반영용)
  PolicyHistory append(PolicyHistoryEntry entry) {
    final merged = [..._entries, entry]
      ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    return PolicyHistory._(merged);
  }

  List<PolicyHistoryEntry> get entries => List.unmodifiable(_entries);
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
