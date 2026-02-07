// lib/data/my_store_join_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ui_calendar_models.dart';
import '../models/alba_form_models.dart';

import '../policies/policies.dart' as pol;
import '../policies/policy_mapper.dart' as pm;

import '../payroll/payroll.dart';
import '../payroll/payroll_policy_mapper.dart' as ppm;

/// ✅ ScheduleRepository가 쓰는 “활성 조인 경로”
class ActiveJoinPath {
  final String ownerUid;
  final String storeId;
  final String? employmentId;

  ActiveJoinPath({
    required this.ownerUid,
    required this.storeId,
    required this.employmentId,
  });
}

class MyStoreJoinRepository {
  MyStoreJoinRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('storeJoins');

  bool _isActiveJoin(Map<String, dynamic> m) {
    // ✅ status가 없으면 예전 데이터일 수 있으니 "active 취급"
    final s = (m['status'] as String?)?.trim().toLowerCase();
    return (s == null || s.isEmpty || s == 'active');
  }

  // ✅ 안전한 timestamp 파서 (레거시/누락/문자열까지 방어)
  DateTime _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ✅ 최근순 정렬키: updatedAt > joinedAt > createdAt > epoch
  DateTime _recentKey(Map<String, dynamic> m) {
    final u = _tsToDate(m['updatedAt']);
    if (u.millisecondsSinceEpoch != 0) return u;

    final j = _tsToDate(m['joinedAt']);
    if (j.millisecondsSinceEpoch != 0) return j;

    final c = _tsToDate(m['createdAt']);
    if (c.millisecondsSinceEpoch != 0) return c;

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ “활성 조인(=status active)”만 뽑아서 ownerUid/storeId를 넘겨주는 스트림
  /// - AppShell이 “조인 근무 스케줄 구독”할 때 사용
  Stream<List<ActiveJoinPath>> watchActiveJoinPaths(String uid) {
    return _ref(uid).snapshots().map((snap) {
      final out = <ActiveJoinPath>[];

      for (final d in snap.docs) {
        final m = d.data();
        if (!_isActiveJoin(m)) continue;

        final storeId = ((m['storeId'] as String?) ?? d.id).trim();
        if (storeId.isEmpty) continue;

        final ownerUid = (m['ownerUid'] as String?)?.trim() ?? '';
        if (ownerUid.isEmpty) continue;

        final employmentId = (m['employmentId'] as String?)?.trim();
        final normalizedEmploymentId =
            (employmentId == null || employmentId.isEmpty)
                ? null
                : employmentId;

        out.add(
          ActiveJoinPath(
            ownerUid: ownerUid,
            storeId: storeId,
            employmentId: normalizedEmploymentId,
          ),
        );
      }

      // 안정화를 위해 정렬(재구독 순서가 흔들리면 디버깅이 어려움)
      out.sort((a, b) {
        final t = a.ownerUid.compareTo(b.ownerUid);
        if (t != 0) return t;
        return a.storeId.compareTo(b.storeId);
      });

      return out;
    });
  }

  /// ✅ 홈 화면 “알바 리스트” 용 (조인한 매장들)
  Stream<List<UICalendarAlba>> watchMyAlbas(String uid) {
    // ✅ 장기 안정화:
    // - Firestore orderBy(updatedAt) 제거
    // - 내 조인 매장 수는 많아야 수십개라 로컬 정렬이 가장 안전
    return _ref(uid).snapshots().map((snap) {
      final items = <({UICalendarAlba alba, DateTime recent})>[];

      for (final d in snap.docs) {
        final m = d.data();

        // ✅ ended는 리스트에서 제외 (세무용 기록은 남겨두고 UI에서 숨김)
        if (!_isActiveJoin(m)) continue;

        // ✅ storeId는 doc id 또는 필드에서 안전하게 가져옴
        final storeId = ((m['storeId'] as String?) ?? d.id).trim();
        if (storeId.isEmpty) continue;

        // ✅ 알바가 매장명을 "내가 보기 편하게" 바꾸는 기능 대비:
        final alias = (m['storeAliasName'] as String?)?.trim();
        final storeName = (m['storeName'] as String?)?.trim();
        final name = (alias != null && alias.isNotEmpty)
            ? alias
            : ((storeName != null && storeName.isNotEmpty) ? storeName : '매장');

        final colorHex = (m['colorHex'] as String?) ?? '#3B82F6';

        // ✅ join 스냅샷 wage: defaultHourlyWage/hourlyWage 둘 다 대응
        final wage =
            _toInt(m['defaultHourlyWage']) ?? _toInt(m['hourlyWage']) ?? 0;

        final payDay = (_toInt(m['payDay']) ?? 25).clamp(1, 31);

        items.add((
          alba: UICalendarAlba(
            // ✅ join 알바는 albaId == storeId
            id: storeId,
            storeId: storeId,
            name: name,
            colorHex: colorHex,
            hourlyWage: wage,
            payDay: payDay,
          ),
          recent: _recentKey(m),
        ));
      }

      // ✅ 정렬: (1) 최근순 (2) 이름
      items.sort((a, b) {
        final t = b.recent.compareTo(a.recent);
        if (t != 0) return t;
        return a.alba.name.compareTo(b.alba.name);
      });

      return items.map((e) => e.alba).toList();
    });
  }

  /// ✅ 조인 매장 “기본 정책/급여정책 스냅샷” 스트림
  Stream<Map<String, AlbaStoreDefaultsSnapshot>> watchMyStoreDefaults(
      String uid) {
    return _ref(uid).snapshots().map((snap) {
      final map = <String, AlbaStoreDefaultsSnapshot>{};

      for (final d in snap.docs) {
        final m = d.data();

        if (!_isActiveJoin(m)) continue;

        final storeId = ((m['storeId'] as String?) ?? d.id).trim();
        if (storeId.isEmpty) continue;

        final payDay = (_toInt(m['payDay']) ?? 25).clamp(1, 31);
        final hourlyWage =
            _toInt(m['defaultHourlyWage']) ?? _toInt(m['hourlyWage']) ?? 0;

        final policy = (m['policy'] as Map?)?.cast<String, dynamic>();

        final tax = pm.taxConfigFromPolicy(policy);
        final ins = pm.insuranceConfigFromPolicy(policy);
        final sur = pm.surchargePolicyFromPolicy(policy);

        PayrollPolicy payroll;
        final rawPayroll = policy?['payrollPolicy'];
        if (rawPayroll is Map) {
          payroll =
              ppm.payrollPolicyFromMap(rawPayroll.cast<String, dynamic>());
        } else {
          final now = DateTime.now();
          payroll = PayrollPolicy(
            cycle: PayCycleType.monthly,
            startFrom: DateTime(now.year, now.month, now.day),
            monthlyStartDay: 1,
            payRule: PayDateRule.nextMonthlyDay(payDay),
          );
        }

        map[storeId] = AlbaStoreDefaultsSnapshot(
          hourlyWage: hourlyWage,
          tax: tax,
          insurance: ins,
          surcharge: sur,
          payrollPolicy: payroll,
          payDay: payDay,
        );
      }

      return map;
    });
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}
