// lib/data/firebase_service.dart
// ✅ 철로 통합: 모든 Firebase 데이터 로직을 한 곳에서 관리
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';
import '../models/store_join_ref.dart';
import '../models/ui_calendar_models.dart';
import '../models/policy_history.dart';
import '../models/alba_form_models.dart';

import '../policies/policies.dart' as pol;
import '../policies/policy_mapper.dart' as pm;
import '../payroll/payroll.dart';
import '../payroll/payroll_policy_mapper.dart' as ppm;

/// ✅ ScheduleRepository가 쓰는 "활성 조인 경로"
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

/// ✅ 철로 통합 서비스
/// - Store, Worker, Schedule 모든 데이터 로직
/// - 중복 제거, 유지보수 쉬움
class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ═══════════════════════════════════════════════
  // 공용 헬퍼 함수들
  // ═══════════════════════════════════════════════

  /// ✅ 안전한 Timestamp → DateTime 변환
  DateTime _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ 날짜 키 생성 (정렬용)
  int _dateKey(int y, int m, int d) => (y * 10000 + m * 100 + d);

  /// ✅ 최근 키 계산 (정렬용)
  DateTime _recentKey(Map<String, dynamic> m) {
    final u = _tsToDate(m['updatedAt']);
    if (u.millisecondsSinceEpoch != 0) return u;

    final c = _tsToDate(m['createdAt']);
    if (c.millisecondsSinceEpoch != 0) return c;

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ═══════════════════════════════════════════════
  // 📍 경로 헬퍼들
  // ═══════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _storesRef(String uid) =>
      _db.collection('users').doc(uid).collection('stores');

  CollectionReference<Map<String, dynamic>> get _joinCodesRef =>
      _db.collection('storeJoinCodes');

  CollectionReference<Map<String, dynamic>> _workersRef({
    required String ownerUid,
    required String storeId,
  }) =>
      _db
          .collection('users')
          .doc(ownerUid)
          .collection('stores')
          .doc(storeId)
          .collection('workers');

  DocumentReference<Map<String, dynamic>> _workerDoc({
    required String ownerUid,
    required String storeId,
    required String workerUid,
  }) =>
      _workersRef(ownerUid: ownerUid, storeId: storeId).doc(workerUid);

  CollectionReference<Map<String, dynamic>> _myStoreJoinsRef(String myUid) =>
      _db.collection('users').doc(myUid).collection('storeJoins');

  String joinIdOf(String ownerUid, String storeId) => '${ownerUid}_$storeId';

  DocumentReference<Map<String, dynamic>> _myStoreJoinDoc({
    required String myUid,
    required String ownerUid,
    required String storeId,
  }) =>
      _myStoreJoinsRef(myUid).doc(joinIdOf(ownerUid, storeId));

  /// ✅ 기존 storeJoins 문서를 쿼리로 찾음 (ID 형식 무관)
  /// 구 자동ID / storeId / {ownerUid}_{storeId} 등 어떤 형식이든 찾음
  /// 없으면 새 형식(joinIdOf) ref 반환
  Future<DocumentReference<Map<String, dynamic>>> _resolveStoreJoinRef({
    required String workerUid,
    required String ownerUid,
    required String storeId,
  }) async {
    final qs = await _myStoreJoinsRef(workerUid)
        .where('ownerUid', isEqualTo: ownerUid)
        .where('storeId', isEqualTo: storeId)
        .limit(1)
        .get();
    if (qs.docs.isNotEmpty) return qs.docs.first.reference;
    // 없으면 새 형식 doc 반환 (create됨)
    return _myStoreJoinDoc(
        myUid: workerUid, ownerUid: ownerUid, storeId: storeId);
  }

  CollectionReference<Map<String, dynamic>> _storeSchedulesRef({
    required String ownerUid,
    required String storeId,
  }) =>
      _db
          .collection('users')
          .doc(ownerUid)
          .collection('stores')
          .doc(storeId)
          .collection('schedules');

  CollectionReference<Map<String, dynamic>> _mySchedulesRef(String myUid) =>
      _db.collection('users').doc(myUid).collection('mySchedules');

  // ═══════════════════════════════════════════════
  // 🏪 STORE 관리 (매장)
  // ═══════════════════════════════════════════════

  /// ✅ 매장 목록 실시간 구독
  Stream<List<Store>> watchStores(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return const Stream<List<Store>>.empty();

    return _storesRef(id).snapshots().map((qs) {
      final docs = qs.docs.toList(growable: false);

      // 로컬 정렬: 최근 수정/생성 순
      final sorted = [...docs];
      sorted.sort((a, b) {
        final ak = _recentKey(a.data());
        final bk = _recentKey(b.data());
        final t = bk.compareTo(ak);
        if (t != 0) return t;

        final an = ((a.data()['name'] ?? '') as String).trim();
        final bn = ((b.data()['name'] ?? '') as String).trim();
        return an.compareTo(bn);
      });

      return sorted.map(Store.fromDoc).toList();
    });
  }

  /// ✅ 매장 생성 (초대 코드 자동 생성)
  Future<Store> createStore({
    required String uid,
    required String name,
    String? colorHex,
    required int defaultHourlyWage,
    required int payDay,
    Map<String, dynamic>? policy,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) throw StateError('uid empty');

    final storeRef = _storesRef(id).doc();
    final code = await _generateUniqueStoreCode();
    final trimmedName = name.trim();

    final storeData = <String, dynamic>{
      'ownerUid': id,
      'name': trimmedName,
      'colorHex': colorHex,
      'defaultHourlyWage': defaultHourlyWage,
      'payDay': payDay,
      'storeCode': code,
      if (policy != null) 'policy': policy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final joinData = <String, dynamic>{
      'ownerUid': id,
      'storeId': storeRef.id,
      'storeName': trimmedName,
      'colorHex': colorHex,
      'defaultHourlyWage': defaultHourlyWage,
      'payDay': payDay,
      'storeCode': code,
      if (policy != null) 'policy': policy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(storeRef, storeData);
    batch.set(_joinCodesRef.doc(code), joinData);
    await batch.commit();

    return Store(
      id: storeRef.id,
      ownerUid: id,
      name: trimmedName,
      colorHex: colorHex,
      defaultHourlyWage: defaultHourlyWage,
      payDay: payDay,
      storeCode: code,
      policy: policy,
      createdAt: null,
      updatedAt: null,
    );
  }

  /// ✅ 매장 정보 수정
  Future<void> updateStore({
    required String uid,
    required String storeId,
    String? name,
    String? colorHex,
    int? defaultHourlyWage,
    int? payDay,
    Map<String, dynamic>? policy,
  }) async {
    final id = uid.trim();
    final sid = storeId.trim();
    if (id.isEmpty) throw StateError('uid empty');
    if (sid.isEmpty) throw StateError('storeId empty');

    final storeDoc = _storesRef(id).doc(sid);

    final snap = await storeDoc.get();
    final current = snap.data() ?? <String, dynamic>{};
    final storeCode = (current['storeCode'] ?? '') as String;

    final storeUpdates = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (colorHex != null) 'colorHex': colorHex,
      if (defaultHourlyWage != null) 'defaultHourlyWage': defaultHourlyWage,
      if (payDay != null) 'payDay': payDay,
      if (policy != null) 'policy': policy,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.update(storeDoc, storeUpdates);

    await batch.commit();

    final code = storeCode.trim();

    // storeJoinCodes는 별도 처리 (권한 실패해도 매장 업데이트는 유지)
    if (code.isNotEmpty) {
      try {
        await _joinCodesRef.doc(code).set(
          <String, dynamic>{
            if (name != null) 'storeName': name.trim(),
            if (colorHex != null) 'colorHex': colorHex,
            if (defaultHourlyWage != null)
              'defaultHourlyWage': defaultHourlyWage,
            if (payDay != null) 'payDay': payDay,
            if (policy != null) 'policy': policy,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[updateStore] storeJoinCodes 업데이트 실패(무시): $e');
      }
    }

    // ✅ 매장 정책 변경 이력 저장 (매장 doc에도)
    if (policy != null) {
      final today = DateTime.now();
      final todayStr = _dateKey(today.year, today.month, today.day);
      final histEntry = {...policy, 'effectiveFrom': todayStr};
      await storeDoc.set(
        {
          'policyHistory': FieldValue.arrayUnion([histEntry])
        },
        SetOptions(merge: true),
      );
    }

    // ✅ inheritFromStore=true 인 알바생 storeJoins 즉시 전파
    // 기존 시급을 읽어서 과거 스케줄 고정에 사용
    final previousWage = (current['defaultHourlyWage'] as num?)?.toInt();
    _propagateStoreDefaultsToWorkers(
      ownerUid: id,
      storeId: sid,
      defaultHourlyWage: defaultHourlyWage,
      payDay: payDay,
      policy: policy,
      previousWage: previousWage,
    );
  }

  /// ✅ 매장 기본 설정 → inheritFromStore=true인 알바생 storeJoins에 전파
  /// 비동기 fire-and-forget (실패해도 앱 흐름에 영향 없음)
  void _propagateStoreDefaultsToWorkers({
    required String ownerUid,
    required String storeId,
    int? defaultHourlyWage,
    int? payDay,
    Map<String, dynamic>? policy,
    int? previousWage, // ✅ 변경 전 시급 (과거 스케줄 고정용)
    DateTime? effectiveFrom, // ✅ 실제 적용 시작일 (null=오늘)
  }) {
    if (defaultHourlyWage == null && payDay == null && policy == null) return;

    Future.microtask(() async {
      try {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);

        // ① 이 매장 workers 목록 가져오기
        final workers =
            await _workersRef(ownerUid: ownerUid, storeId: storeId).get();
        if (workers.docs.isEmpty) return;

        for (final workerDoc in workers.docs) {
          final wData = workerDoc.data();
          // inheritFromStore=false면 건너뜀 (개인 설정 우선)
          final inherit = (wData['inheritFromStore'] as bool?) ?? true;
          if (!inherit) {
            debugPrint('[propagate] skip ${workerDoc.id} (개인 설정)');
            continue;
          }

          final workerUid = workerDoc.id;

          try {
            // ✅ 시급이 바뀐 경우: 오늘 이전 스케줄에 기존 시급 고정
            // (오늘부터 새 시급 적용이므로 오늘 이전 = 기존 시급)
            if (defaultHourlyWage != null &&
                previousWage != null &&
                defaultHourlyWage != previousWage) {
              final untilKey =
                  _dateKey(todayDate.year, todayDate.month, todayDate.day);
              final pastSnap = await _storeSchedulesRef(
                ownerUid: ownerUid,
                storeId: storeId,
              )
                  .where('workerUid', isEqualTo: workerUid)
                  .where('dateKey', isLessThan: untilKey)
                  .get();
              // ✅ [BUG FIX] isNull 필터 → 메모리 필터로 대체 (복합 인덱스 불필요)
              final pastDocs = pastSnap.docs
                  .where((d) => d.data()['overrideHourlyWage'] == null)
                  .toList();

              if (pastDocs.isNotEmpty) {
                const batchSize = 400;
                final docs = pastDocs;
                for (int i = 0; i < docs.length; i += batchSize) {
                  final chunk = docs.skip(i).take(batchSize).toList();
                  final b = _db.batch();
                  for (final d in chunk) {
                    b.set(
                        d.reference,
                        {
                          'overrideHourlyWage': previousWage,
                          'updatedAt': FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true));
                  }
                  await b.commit();
                }
                debugPrint(
                    '[propagate] ✓ $workerUid 과거 스케줄 시급 고정 (${previousWage}원)');
              }

              // ✅ 오늘 이후 스케줄에 새 시급 적용
              final futureKey =
                  _dateKey(todayDate.year, todayDate.month, todayDate.day);
              final futureSnap = await _storeSchedulesRef(
                ownerUid: ownerUid,
                storeId: storeId,
              )
                  .where('workerUid', isEqualTo: workerUid)
                  .where('dateKey', isGreaterThanOrEqualTo: futureKey)
                  .get();

              if (futureSnap.docs.isNotEmpty) {
                const batchSize = 400;
                final docs = futureSnap.docs;
                for (int i = 0; i < docs.length; i += batchSize) {
                  final chunk = docs.skip(i).take(batchSize).toList();
                  final b = _db.batch();
                  for (final d in chunk) {
                    b.set(
                        d.reference,
                        {
                          'overrideHourlyWage': defaultHourlyWage,
                          'updatedAt': FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true));
                  }
                  await b.commit();
                }
                debugPrint(
                    '[propagate] ✓ $workerUid 오늘 이후 스케줄 새 시급 적용 (${defaultHourlyWage}원)');
              }
            }

            // ② 알바생 storeJoins 업데이트 (기존 doc ID 그대로 사용)
            // ✅ 쿼리로 기존 문서 찾기 (구 자동ID 포함)
            final joinRef = await _resolveStoreJoinRef(
              workerUid: workerUid,
              ownerUid: ownerUid,
              storeId: storeId,
            );
            final joinSnap = await joinRef.get();
            if (!joinSnap.exists) continue;

            // ✅ ownerSetting도 함께 업데이트 → 알바 앱 즉시 반영
            final ownerSettingUpdate = <String, dynamic>{
              if (defaultHourlyWage != null) 'hourlyWage': defaultHourlyWage,
              if (payDay != null) 'payDay': payDay,
              if (policy != null) 'policy': policy,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            final joinUpdates = <String, dynamic>{
              'ownerUid': ownerUid, // ✅ Firestore rules 사장님 권한 검증용
              'storeId': storeId,
              if (defaultHourlyWage != null) ...{
                'hourlyWage': defaultHourlyWage,
                'defaultHourlyWage': defaultHourlyWage,
              },
              if (payDay != null) 'payDay': payDay,
              if (policy != null) 'policy': policy,
              'ownerSetting': ownerSettingUpdate,
              'updatedAt': FieldValue.serverTimestamp(),
            };

            // ✅ 정책·시급 변경 이력 전파
            // policy 또는 defaultHourlyWage 중 하나라도 있으면 이력 생성
            if (policy != null || defaultHourlyWage != null) {
              final effectiveDate = effectiveFrom ?? DateTime.now();
              final effectiveDateStr = _dateKey(
                  effectiveDate.year, effectiveDate.month, effectiveDate.day);
              final histEntry = {
                if (policy != null) ...policy,
                if (defaultHourlyWage != null) 'hourlyWage': defaultHourlyWage,
                if (previousWage != null) 'previousHourlyWage': previousWage,
                'effectiveFrom': effectiveDateStr,
              };
              await joinRef.set(
                {
                  'policyHistory': FieldValue.arrayUnion([histEntry])
                },
                SetOptions(merge: true),
              );
            }
            await joinRef.set(joinUpdates, SetOptions(merge: true));
            debugPrint('[propagate] ✓ ${workerUid} storeJoins 업데이트');
          } catch (e) {
            debugPrint('[propagate] $workerUid 업데이트 실패: $e');
          }
        }
      } catch (e) {
        debugPrint('[propagate] workers 조회 실패: $e');
      }
    });
  }

  /// ✅ 매장 삭제
  Future<void> deleteStore({
    required String uid,
    required String storeId,
    String? storeCode,
  }) async {
    final id = uid.trim();
    final sid = storeId.trim();
    if (id.isEmpty) throw StateError('uid empty');
    if (sid.isEmpty) throw StateError('storeId empty');

    // ① 매장 doc 삭제 (항상 가능 - 본인 데이터)
    await _storesRef(id).doc(sid).delete();

    // ② 초대 코드 삭제 (별도 처리 - 권한 규칙 필요)
    final code = storeCode?.trim();
    if (code != null && code.isNotEmpty) {
      try {
        await _joinCodesRef.doc(code).delete();
      } catch (e) {
        // storeJoinCodes 삭제 권한 없으면 무효화만
        try {
          await _joinCodesRef.doc(code).set({
            'deleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {
          debugPrint('[deleteStore] 초대코드 정리 실패: $code');
        }
      }
    }

    // ② workers 서브컬렉션 삭제 (비동기, 실패해도 계속)
    try {
      final workers = await _workersRef(ownerUid: id, storeId: sid).get();
      if (workers.docs.isNotEmpty) {
        final wBatch = _db.batch();
        for (final doc in workers.docs) {
          wBatch.delete(doc.reference);
        }
        await wBatch.commit();
      }
    } catch (e) {
      debugPrint('[deleteStore] workers 정리 실패: $e');
    }
  }

  /// ✅ 초대 코드로 매장 정보 가져오기
  Future<StoreJoinRef?> resolveJoinRefByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;

    final doc = await _joinCodesRef.doc(c).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    final ownerUid = (data['ownerUid'] ?? '') as String;
    final storeId = (data['storeId'] ?? '') as String;
    if (ownerUid.isEmpty || storeId.isEmpty) return null;

    return StoreJoinRef(ownerUid: ownerUid, storeId: storeId);
  }

  /// ✅ 초대 코드 메타 정보
  Future<Map<String, dynamic>?> fetchJoinCodeMeta(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;

    final doc = await _joinCodesRef.doc(c).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    final ownerUid = (data['ownerUid'] ?? '') as String;
    final storeId = (data['storeId'] ?? '') as String;
    if (ownerUid.isEmpty || storeId.isEmpty) return null;

    return data;
  }

  /// ✅ JoinRef로 Store 가져오기
  Future<Store?> fetchStoreByJoinRef(StoreJoinRef ref) async {
    final doc = await _storesRef(ref.ownerUid).doc(ref.storeId).get();
    if (!doc.exists) return null;
    return Store.fromDoc(doc);
  }

  /// ✅ 중복 없는 초대 코드 생성
  Future<String> _generateUniqueStoreCode() async {
    // 4자리, 대소문자 구분 / 혼동 문자 제외(0·O·o, 1·I·l)
    // 소문자24 + 대문자24 + 숫자8 = 56자 → 56^4 ≈ 987만 가지
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();

    String gen() {
      final sb = StringBuffer();
      for (int i = 0; i < 4; i++) {
        sb.write(chars[r.nextInt(chars.length)]);
      }
      return sb.toString();
    }

    for (int i = 0; i < 30; i++) {
      final code = gen();
      final exists = (await _joinCodesRef.doc(code).get()).exists;
      if (!exists) return code;
    }
    return gen();
  }

  // ═══════════════════════════════════════════════
  // 👥 WORKER 관리 (근무자)
  // ═══════════════════════════════════════════════

  /// ✅ 근무자 목록 실시간 구독
  Stream<List<StoreWorker>> watchWorkers({
    required String ownerUid,
    required String storeId,
    bool activeOnly = true,
  }) {
    Query<Map<String, dynamic>> q =
        _workersRef(ownerUid: ownerUid, storeId: storeId);

    if (activeOnly) {
      q = q.where('status', isEqualTo: 'active');
    }

    return q.orderBy('joinedAt', descending: true).snapshots().map((snap) {
      return snap.docs
          .map((d) => StoreWorker.fromJson(d.data()))
          .toList(growable: false);
    });
  }

  /// ✅ 근무자 설정 저장
  Future<void> saveWorkerSettings({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String? displayName,
    required bool inheritFromStore,
    int? hourlyWage,
    int? previousHourlyWage, // ✅ 변경 전 시급 (이력 저장용)
    int? payDay,
    Map<String, dynamic>? policyOverride,
    DateTime? effectiveFrom, // ✅ 시급 몇일부터 적용 (null = 즉시)
    DateTime? policyEffectiveFrom, // ✅ 가산정책 몇일부터 적용 (null = 오늘)
  }) async {
    final nowServer = FieldValue.serverTimestamp();

    final today = DateTime.now();
    String toYmd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    // 정책 적용일: 지정되면 그날, 없으면 오늘
    final policyDate = policyEffectiveFrom ?? today;
    final policyDateStr = toYmd(policyDate);

    // 시급 적용일: effectiveFrom이 지정되면 그날, 없으면 오늘
    final wageDate = effectiveFrom ?? today;
    final wageDateStr = toYmd(wageDate);

    // ✅ 시급·정책 이력을 적용일 기준으로 분리 저장
    // 시급만 변경: wageDateStr 기준 항목
    // 정책만 변경: policyDateStr 기준 항목
    // 둘 다 같은 날: 하나의 항목으로 합침

    // 시급/정책 적용일이 같으면 하나로, 다르면 각각
    // ✅ 핵심: 시급 변경 시 이전 시급을 "1970-01-01" 초기 밴드로 명시 저장
    // → 기준일 이전 날짜 근무 추가 시 항상 이전 시급이 정확히 반환됨
    // 정책도 동일하게 기준일 밴드로 저장
    final histEntries = <Map<String, dynamic>>[];

    if (hourlyWage != null && previousHourlyWage != null) {
      // ✅ 시급 변경: 새 시급 밴드만 추가
      // 1970-01-01 앵커는 최초 등록 시 이미 설정되어 있으므로 중복 추가 금지
      // (arrayUnion이 다른 hourlyWage 값이면 별도 항목으로 추가하기 때문)
      histEntries.add({'hourlyWage': hourlyWage, 'effectiveFrom': wageDateStr});
    } else if (hourlyWage != null) {
      // 최초 등록 (이전 시급 없음)
      histEntries
          .add({'hourlyWage': hourlyWage, 'effectiveFrom': '1970-01-01'});
    }

    if (policyOverride != null) {
      // ③ 정책 밴드 (기준일부터 적용)
      histEntries.add({
        ...policyOverride!,
        if (hourlyWage != null) 'hourlyWage': hourlyWage,
        'effectiveFrom': policyDateStr,
      });
    }

    final policyHistoryEntry = histEntries.isNotEmpty ? histEntries : null;

    // ① 사장님 worker doc에 저장 (항상 성공)
    // ✅ 미래 날짜부터 적용인 경우: 현재 시급/정책은 유지, policyHistory에만 추가
    final todayDate = DateTime(today.year, today.month, today.day);
    final wageIsNow =
        effectiveFrom == null || !effectiveFrom.isAfter(todayDate);
    final policyIsNow =
        policyEffectiveFrom == null || !policyEffectiveFrom.isAfter(todayDate);

    await _workerDoc(ownerUid: ownerUid, storeId: storeId, workerUid: workerUid)
        .set({
      'workerUid': workerUid,
      if (displayName != null) 'displayName': displayName,
      'inheritFromStore': inheritFromStore,
      // 시급: effectiveFrom이 오늘 이전/당일이면 즉시 반영, 미래면 이력만 추가
      if (hourlyWage != null && wageIsNow) 'hourlyWage': hourlyWage,
      if (payDay != null) 'payDay': payDay,
      // 정책: policyEffectiveFrom이 오늘 이전/당일이면 즉시 반영
      if (policyOverride != null && policyIsNow)
        'policyOverride': policyOverride,
      if (policyHistoryEntry != null)
        'policyHistory': FieldValue.arrayUnion(policyHistoryEntry),
      'updatedAt': nowServer,
      if (effectiveFrom != null)
        'effectiveFrom': Timestamp.fromDate(effectiveFrom),
    }, SetOptions(merge: true));

    // ② 알바생 storeJoins doc에도 동기화 (기존 doc ID 그대로 사용)
    try {
      final joinRef = await _resolveStoreJoinRef(
        workerUid: workerUid,
        ownerUid: ownerUid,
        storeId: storeId,
      );
      await joinRef.set({
        'ownerUid': ownerUid, // ✅ Firestore rules 사장님 권한 검증용
        'storeId': storeId, // ✅ 조회 편의
        'inheritFromStore': inheritFromStore,
        // ✅ 미래 날짜부터 적용인 경우: 현재 시급/정책 유지
        if (hourlyWage != null && wageIsNow) ...{
          'hourlyWage': hourlyWage,
          'defaultHourlyWage': hourlyWage,
        },
        if (payDay != null) 'payDay': payDay,
        if (policyOverride != null && policyIsNow) 'policy': policyOverride,
        if (policyHistoryEntry != null)
          'policyHistory': FieldValue.arrayUnion(policyHistoryEntry),
        // ✅ ownerSetting: 사장님이 마지막으로 설정한 값 (알바가 읽음)
        'ownerSetting': {
          'inheritFromStore': inheritFromStore,
          if (hourlyWage != null && wageIsNow) 'hourlyWage': hourlyWage,
          if (payDay != null) 'payDay': payDay,
          if (policyOverride != null && policyIsNow) 'policy': policyOverride,
          if (effectiveFrom != null)
            'effectiveFrom': Timestamp.fromDate(effectiveFrom),
          'updatedAt': nowServer,
        },
        'updatedAt': nowServer,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[saveWorkerSettings] storeJoins 동기화 실패: $e');
    }
  }

  /// ✅ 근무자 내보내기 (삭제 아님!)
  Future<void> endWorker({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String reason = 'kicked',
  }) async {
    final nowLocal = DateTime.now();
    final nowServer = FieldValue.serverTimestamp();

    await _workerDoc(ownerUid: ownerUid, storeId: storeId, workerUid: workerUid)
        .set({
      'status': 'ended',
      'endedReason': reason,
      'endedAt': nowServer,
      'endedAtLocal': Timestamp.fromDate(nowLocal),
      'updatedAt': nowServer,
    }, SetOptions(merge: true));

    try {
      await _myStoreJoinDoc(
        myUid: workerUid,
        ownerUid: ownerUid,
        storeId: storeId,
      ).set({
        'status': 'ended',
        'endedReason': reason,
        'endedAt': nowServer,
        'endedAtLocal': Timestamp.fromDate(nowLocal),
        'updatedAt': nowServer,
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  /// ✅ 호환용 (소문자 메서드)
  Future<void> endworker({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String reason = 'kicked',
  }) =>
      endWorker(
        ownerUid: ownerUid,
        storeId: storeId,
        workerUid: workerUid,
        reason: reason,
      );

  /// ✅ 호환용 (removeWorker → endWorker)
  Future<void> removeWorker({
    required String ownerUid,
    required String storeId,
    required String workerUid,
  }) async {
    await endWorker(
      ownerUid: ownerUid,
      storeId: storeId,
      workerUid: workerUid,
      reason: 'kicked',
    );
  }

  /// ✅ 초대 코드로 입장하기 (알바생)
  Future<Store?> joinByCode({
    required String code,
    required bool applyDefaults,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');

    final normalized = code.trim().replaceAll(' ', '');
    final ref = await resolveJoinRefByCode(normalized);
    if (ref == null) return null;

    await _workerDoc(
      ownerUid: ref.ownerUid,
      storeId: ref.storeId,
      workerUid: user.uid,
    ).set({
      'workerUid': user.uid,
      'displayName': user.displayName,
      'inheritFromStore': applyDefaults,
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final store = await fetchStoreByJoinRef(ref);
    if (store == null) {
      try {
        await _workerDoc(
          ownerUid: ref.ownerUid,
          storeId: ref.storeId,
          workerUid: user.uid,
        ).delete();
      } catch (_) {}
      return null;
    }

    final jid = joinIdOf(ref.ownerUid, ref.storeId);

    await _myStoreJoinsRef(user.uid).doc(jid).set({
      'id': jid,
      'workerUid': user.uid,
      'ownerUid': ref.ownerUid,
      'storeId': ref.storeId,
      'storeName': store.name,
      'storeCode': store.storeCode ?? normalized,
      'defaultHourlyWage': store.defaultHourlyWage,
      'hourlyWage': store.defaultHourlyWage,
      'payDay': store.payDay,
      'colorHex': store.colorHex,
      'policy': store.policy,
      'inheritFromStore': applyDefaults,
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
      'endedAtLocal': FieldValue.delete(),
      'endedReason': FieldValue.delete(),
    }, SetOptions(merge: true));

    return store;
  }

  // ═══════════════════════════════════════════════
  // 📅 SCHEDULE 관리 (근무 스케줄)
  // ═══════════════════════════════════════════════

  /// ✅ docPath로 스케줄 삭제
  Future<void> deleteScheduleByDocPath(String docPath) async {
    if (docPath.trim().isEmpty) throw StateError('docPath가 비어있어요.');
    await _db.doc(docPath).delete();
  }

  /// ✅ docPath로 스케줄 수정
  Future<void> updateScheduleByDocPath({
    required String docPath,
    required Map<String, dynamic> data,
  }) async {
    if (docPath.trim().isEmpty) throw StateError('docPath가 비어있어요.');
    await _db.doc(docPath).set(data, SetOptions(merge: true));
  }

  /// ✅ 개인 스케줄 구독 (알바생)
  Stream<List<UICalendarSchedule>> watchMyPersonalSchedulesUiRecentDays({
    required String workerUid,
    int recentDays = 120,
  }) {
    if (workerUid.isEmpty) {
      return const Stream<List<UICalendarSchedule>>.empty();
    }

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (recentDays <= 0 ? 1 : recentDays) - 1));
    final startKey = _dateKey(start.year, start.month, start.day);

    return _mySchedulesRef(workerUid)
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map(_uiFromPersonalDoc).toList(growable: false));
  }

  /// ✅ 조인 스케줄 구독 (알바생)
  Stream<List<UICalendarSchedule>> watchMyJoinSchedulesByActiveJoins({
    required String workerUid,
    required Stream<List<ActiveJoinPath>> activeJoins$,
    int recentDays = 120,
  }) {
    if (workerUid.isEmpty) {
      return const Stream<List<UICalendarSchedule>>.empty();
    }

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (recentDays <= 0 ? 1 : recentDays) - 1));
    final startKey = _dateKey(start.year, start.month, start.day);

    late StreamController<List<UICalendarSchedule>> controller;
    StreamSubscription? joinsSub;

    final Map<String, StreamSubscription> perStoreSubs = {};
    final Map<String, List<UICalendarSchedule>> latestByStore = {};

    void emit() {
      final merged = <UICalendarSchedule>[];
      for (final v in latestByStore.values) {
        merged.addAll(v);
      }
      merged.sort((x, y) {
        final dx = x.year * 10000 + x.month * 100 + x.day;
        final dy = y.year * 10000 + y.month * 100 + y.day;
        if (dx != dy) return dx.compareTo(dy);
        final sx = x.startHour * 60 + x.startMinute;
        final sy = y.startHour * 60 + y.startMinute;
        if (sx != sy) return sx.compareTo(sy);
        return x.id.compareTo(y.id);
      });
      controller.add(merged);
    }

    Future<void> resubscribe(List<ActiveJoinPath> joins) async {
      final keepKeys = <String>{};

      for (final j in joins) {
        final key = '${j.ownerUid}__${j.storeId}';
        keepKeys.add(key);

        if (perStoreSubs.containsKey(key)) continue;

        final q = _storeSchedulesRef(ownerUid: j.ownerUid, storeId: j.storeId)
            .where('workerUid', isEqualTo: workerUid)
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .orderBy('dateKey', descending: false)
            .orderBy('startMin', descending: false);

        perStoreSubs[key] = q.snapshots().listen((qs) {
          latestByStore[key] =
              qs.docs.map(_uiFromJoinGroupDoc).toList(growable: false);
          emit();
        });
      }

      final removeKeys = perStoreSubs.keys.where((k) => !keepKeys.contains(k));
      for (final k in removeKeys.toList()) {
        await perStoreSubs[k]?.cancel();
        perStoreSubs.remove(k);
        latestByStore.remove(k);
      }

      emit();
    }

    controller = StreamController<List<UICalendarSchedule>>.broadcast(
      onListen: () {
        joinsSub = activeJoins$.listen((joins) {
          resubscribe(joins);
        });
      },
      onCancel: () async {
        await joinsSub?.cancel();
        for (final sub in perStoreSubs.values) {
          await sub.cancel();
        }
        perStoreSubs.clear();
        latestByStore.clear();
        await controller.close();
      },
    );

    return controller.stream;
  }

  /// ✅ 개인+조인 스케줄 합치기
  Stream<List<UICalendarSchedule>> watchMySchedulesUiMergedV2({
    required String workerUid,
    required Stream<List<ActiveJoinPath>> activeJoins$,
    int recentDays = 120,
  }) {
    final join$ = watchMyJoinSchedulesByActiveJoins(
      workerUid: workerUid,
      activeJoins$: activeJoins$,
      recentDays: recentDays,
    );

    final personal$ = watchMyPersonalSchedulesUiRecentDays(
      workerUid: workerUid,
      recentDays: recentDays,
    );

    late StreamController<List<UICalendarSchedule>> controller;
    StreamSubscription? subA;
    StreamSubscription? subB;

    var latestA = const <UICalendarSchedule>[];
    var latestB = const <UICalendarSchedule>[];

    void emit() {
      final merged = <UICalendarSchedule>[...latestA, ...latestB];
      merged.sort((x, y) {
        final dx = x.year * 10000 + x.month * 100 + x.day;
        final dy = y.year * 10000 + y.month * 100 + y.day;
        if (dx != dy) return dx.compareTo(dy);
        final sx = x.startHour * 60 + x.startMinute;
        final sy = y.startHour * 60 + y.startMinute;
        if (sx != sy) return sx.compareTo(sy);
        return x.id.compareTo(y.id);
      });
      controller.add(merged);
    }

    controller = StreamController<List<UICalendarSchedule>>.broadcast(
      onListen: () {
        subA = join$.listen((v) {
          latestA = v;
          emit();
        });
        subB = personal$.listen((v) {
          latestB = v;
          emit();
        });
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }

  /// ✅ 스케줄 추가
  Future<void> addOneFromUi({
    String? ownerUid,
    String? storeId,
    required String workerUid,
    String? employmentId,
    required UICalendarSchedule ui,
  }) async {
    final y = ui.year;
    final m = ui.month;
    final d = ui.day;

    final dateKey = _dateKey(y, m, d);
    final startMin = ui.startHour * 60 + ui.startMinute;

    final payload = <String, dynamic>{
      'workerUid': workerUid,
      if (employmentId != null && employmentId.trim().isNotEmpty)
        'employmentId': employmentId.trim(),
      'albaId': ui.albaId,
      'year': y,
      'month': m,
      'day': d,
      'startHour': ui.startHour,
      'startMinute': ui.startMinute,
      'endHour': ui.endHour,
      'endMinute': ui.endMinute,
      'breakMinutes': ui.breakMinutes,
      'workType': ui.workType.name,
      'overrideHourlyWage': ui.overrideHourlyWage,
      'dateKey': dateKey,
      'startMin': startMin,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // JOIN 스케줄 (사장님 매장에 추가)
    if (ownerUid != null &&
        ownerUid.isNotEmpty &&
        storeId != null &&
        storeId.isNotEmpty) {
      await _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId).add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.fromDate(DateTime.now()),
      });
      return;
    }

    // PERSONAL 스케줄
    await _mySchedulesRef(workerUid).add({
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// ✅ 스케줄 수정
  Future<void> updateScheduleSmart({
    required String workerUid,
    required UICalendarSchedule ui,
  }) async {
    if (ui.id.trim().isEmpty) throw StateError('수정할 scheduleId가 비어있어요.');

    final y = ui.year;
    final m = ui.month;
    final d = ui.day;

    final dateKey = _dateKey(y, m, d);
    final startMin = ui.startHour * 60 + ui.startMinute;

    final data = <String, dynamic>{
      'albaId': ui.albaId,
      'year': y,
      'month': m,
      'day': d,
      'startHour': ui.startHour,
      'startMinute': ui.startMinute,
      'endHour': ui.endHour,
      'endMinute': ui.endMinute,
      'breakMinutes': ui.breakMinutes,
      'workType': ui.workType.name,
      'overrideHourlyWage': ui.overrideHourlyWage,
      'dateKey': dateKey,
      'startMin': startMin,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (ui.docPath != null && ui.docPath!.trim().isNotEmpty) {
      await updateScheduleByDocPath(docPath: ui.docPath!, data: data);
      return;
    }

    await _mySchedulesRef(workerUid)
        .doc(ui.id)
        .set(data, SetOptions(merge: true));
  }

  /// ✅ 개인/조인 알바 스케줄 시급 일괄 적용
  /// - Firestore에서 전체 조회 (메모리 120일 제한 없음)
  /// - todayOnly=true : 오늘 날짜만
  /// - fromDate~untilDate : 범위 지정 (null=제한없음)
  Future<void> bulkUpdateScheduleWage({
    required String workerUid,
    required String albaId,
    required int newWage,
    required List<UICalendarSchedule>
        schedules, // 오늘~미래 범위용 (todayOnly/fromDate)
    bool todayOnly = false,
    DateTime? fromDate,
    DateTime? untilDate, // 이 날짜 직전까지 (과거 고정용)
  }) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final data = <String, dynamic>{
      'overrideHourlyWage': newWage,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // ✅ 과거 스케줄 고정 (untilDate 지정) → Firestore 직접 전체 조회 (범위 무제한)
    if (untilDate != null) {
      final untilKey = _dateKey(untilDate.year, untilDate.month, untilDate.day);
      final fromKey = fromDate != null
          ? _dateKey(fromDate.year, fromDate.month, fromDate.day)
          : null;

      // ✅ [BUG FIX] isNull 필터를 Firestore 쿼리에서 제거.
      //    복합 인덱스(albaId + dateKey + overrideHourlyWage) 없이도 동작하도록
      //    Firestore에서 날짜 범위만 조회한 뒤, 메모리에서 override 없는 것만 필터.
      var q = _mySchedulesRef(workerUid)
          .where('albaId', isEqualTo: albaId)
          .where('dateKey', isLessThan: untilKey);
      if (fromKey != null)
        q = q.where('dateKey', isGreaterThanOrEqualTo: fromKey);
      final personalSnap = await q.get();
      // 이미 override 된 것은 건드리지 않음 (기존 기록 보존) - 메모리 필터
      final personalDocs = personalSnap.docs
          .where((d) => d.data()['overrideHourlyWage'] == null)
          .toList();

      // 조인 스케줄 (docPath 기반)
      final joinDocs = schedules
          .where((s) =>
              s.albaId == albaId && s.docPath != null && s.docPath!.isNotEmpty)
          .toList();
      // 조인 스케줄은 ownerUid/storeId를 docPath에서 파싱해서 재조회
      final Set<String> ownerStorePairs = {};
      for (final s in joinDocs) {
        final parts = s.docPath!.split('/');
        // users/{ownerUid}/stores/{storeId}/schedules/{id}
        if (parts.length >= 6) {
          ownerStorePairs.add('${parts[1]}/${parts[3]}');
        }
      }

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> allJoinDocs = [];
      for (final pair in ownerStorePairs) {
        final parts = pair.split('/');
        final ownerUid2 = parts[0], storeId2 = parts[1];
        // ✅ [BUG FIX] isNull 필터 제거 → 메모리 필터로 대체
        var jq = _storeSchedulesRef(ownerUid: ownerUid2, storeId: storeId2)
            .where('workerUid', isEqualTo: workerUid)
            .where('dateKey', isLessThan: untilKey);
        if (fromKey != null)
          jq = jq.where('dateKey', isGreaterThanOrEqualTo: fromKey);
        final snap = await jq.get();
        // 이미 override 된 것은 건드리지 않음 - 메모리 필터
        allJoinDocs.addAll(
          snap.docs.where((d) => d.data()['overrideHourlyWage'] == null),
        );
      }

      final allDocs = [...personalDocs, ...allJoinDocs];
      if (allDocs.isEmpty) return;

      const batchSize = 400;
      for (int i = 0; i < allDocs.length; i += batchSize) {
        final chunk = allDocs.skip(i).take(batchSize).toList();
        final batch = _db.batch();
        for (final doc in chunk) {
          batch.set(doc.reference, data, SetOptions(merge: true));
        }
        await batch.commit();
      }
      return;
    }

    // ✅ 오늘 이후 스케줄 → 메모리 리스트 사용 (이미 스트림에서 최신 로드됨)
    final effectiveFrom = fromDate ?? todayDate;
    final targets = schedules.where((s) {
      if (s.albaId != albaId) return false;
      final sDate = DateTime(s.year, s.month, s.day);
      if (todayOnly) return sDate == todayDate;
      return !sDate.isBefore(effectiveFrom);
    }).toList();

    if (targets.isEmpty) return;

    const batchSize = 400;
    for (int offset = 0; offset < targets.length; offset += batchSize) {
      final chunk = targets.skip(offset).take(batchSize).toList();
      final batch = _db.batch();
      for (final s in chunk) {
        if (s.docPath != null && s.docPath!.trim().isNotEmpty) {
          batch.set(_db.doc(s.docPath!), data, SetOptions(merge: true));
        } else if (s.id.trim().isNotEmpty) {
          batch.set(_mySchedulesRef(workerUid).doc(s.id), data,
              SetOptions(merge: true));
        }
      }
      await batch.commit();
    }
  }

  /// ✅ 사장님 측 스케줄 시급 일괄 업데이트
  /// - Firestore 직접 전체 조회 (메모리 120일 제한 없음)
  Future<void> bulkUpdateStoreScheduleWage({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    required int newWage,
    required List<StoreSchedule> schedules,
    bool todayOnly = false,
    DateTime? fromDate,
    DateTime? untilDate,
  }) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final data = <String, dynamic>{
      'overrideHourlyWage': newWage,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // ✅ 과거 고정 (untilDate 있음) → Firestore 직접 전체 조회
    if (untilDate != null) {
      final untilKey = _dateKey(untilDate.year, untilDate.month, untilDate.day);
      final fromKey = fromDate != null
          ? _dateKey(fromDate.year, fromDate.month, fromDate.day)
          : null;

      // ✅ workerUid + dateKey 복합 인덱스 불필요: dateKey만 Firestore 필터, workerUid는 메모리 필터
      var q = _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
          .where('dateKey', isLessThan: untilKey);
      if (fromKey != null)
        q = q.where('dateKey', isGreaterThanOrEqualTo: fromKey);

      final snap = await q.get();
      // workerUid 일치 + 이미 override된 스케줄은 건드리지 않음 - 메모리 필터
      final filteredDocs = snap.docs
          .where((d) =>
              d.data()['workerUid'] == workerUid &&
              d.data()['overrideHourlyWage'] == null)
          .toList();
      if (filteredDocs.isEmpty) return;

      const batchSize = 400;
      for (int i = 0; i < filteredDocs.length; i += batchSize) {
        final chunk = filteredDocs.skip(i).take(batchSize).toList();
        final batch = _db.batch();
        for (final doc in chunk) {
          batch.set(doc.reference, data, SetOptions(merge: true));
        }
        await batch.commit();
      }
      return;
    }

    // ✅ 오늘 이후 → 메모리 리스트 사용
    final effectiveFrom = fromDate ?? todayDate;
    final targets = schedules.where((s) {
      if (s.workerUid != workerUid) return false;
      final sDate = DateTime(s.year, s.month, s.day);
      if (todayOnly) return sDate == todayDate;
      return !sDate.isBefore(effectiveFrom);
    }).toList();

    if (targets.isEmpty) return;

    const batchSize = 400;
    for (int offset = 0; offset < targets.length; offset += batchSize) {
      final chunk = targets.skip(offset).take(batchSize).toList();
      final batch = _db.batch();
      for (final s in chunk) {
        final ref =
            _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId).doc(s.id);
        batch.set(ref, data, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  /// ✅ 스케줄 삭제
  Future<void> deleteScheduleSmart({
    required String workerUid,
    required UICalendarSchedule ui,
  }) async {
    if (ui.id.trim().isEmpty) throw StateError('삭제할 scheduleId가 비어있어요.');

    if (ui.docPath != null && ui.docPath!.trim().isNotEmpty) {
      await deleteScheduleByDocPath(ui.docPath!);
      return;
    }

    await _mySchedulesRef(workerUid).doc(ui.id).delete();
  }

  // ═══════════════════════════════════════════════
  // 내부 헬퍼: UI 변환
  // ═══════════════════════════════════════════════

  UICalendarSchedule _uiFromJoinGroupDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final y = (d['year'] as num?)?.toInt() ?? 1970;
    final m = (d['month'] as num?)?.toInt() ?? 1;
    final day = (d['day'] as num?)?.toInt() ?? 1;

    return UICalendarSchedule(
      id: doc.id,
      albaId: (d['albaId'] as String?) ?? '',
      year: y,
      month: m,
      day: day,
      startHour: (d['startHour'] as num?)?.toInt() ?? 0,
      startMinute: (d['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (d['endHour'] as num?)?.toInt() ?? 0,
      endMinute: (d['endMinute'] as num?)?.toInt() ?? 0,
      breakMinutes: (d['breakMinutes'] as num?)?.toInt() ?? 0,
      workType: _workTypeFromString((d['workType'] as String?) ?? 'basic'),
      overrideHourlyWage: (d['overrideHourlyWage'] as num?)?.toInt(),
      docPath: doc.reference.path,
    );
  }

  UICalendarSchedule _uiFromPersonalDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final y = (d['year'] as num?)?.toInt() ?? 1970;
    final m = (d['month'] as num?)?.toInt() ?? 1;
    final day = (d['day'] as num?)?.toInt() ?? 1;

    return UICalendarSchedule(
      id: doc.id,
      albaId: (d['albaId'] as String?) ?? '',
      year: y,
      month: m,
      day: day,
      startHour: (d['startHour'] as num?)?.toInt() ?? 0,
      startMinute: (d['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (d['endHour'] as num?)?.toInt() ?? 0,
      endMinute: (d['endMinute'] as num?)?.toInt() ?? 0,
      breakMinutes: (d['breakMinutes'] as num?)?.toInt() ?? 0,
      workType: _workTypeFromString((d['workType'] as String?) ?? 'basic'),
      overrideHourlyWage: (d['overrideHourlyWage'] as num?)?.toInt(),
      docPath: doc.reference.path,
    );
  }

  WorkType _workTypeFromString(String s) {
    switch (s) {
      case 'substitute':
        return WorkType.substitute;
      case 'night':
        return WorkType.night;
      case 'overtime':
        return WorkType.overtime;
      case 'holiday':
        return WorkType.holiday;
      case 'basic':
      default:
        return WorkType.basic;
    }
  }

  // ═══════════════════════════════════════════════
  // 👥 WORKER 추가 메서드들 (Owner 전용)
  // ═══════════════════════════════════════════════

  /// ✅ sortIndex 없는 근무자들에게 자동으로 부여
  Future<void> ensureSortIndexIfMissing({
    required String ownerUid,
    required String storeId,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty) return;

    final snap = await _workersRef(ownerUid: ownerUid, storeId: storeId).get();
    if (snap.docs.isEmpty) return;

    final missing = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!data.containsKey('sortIndex') || data['sortIndex'] == null) {
        missing.add(d);
      }
    }
    if (missing.isEmpty) return;

    missing.sort((a, b) => a.id.compareTo(b.id));

    final batch = _db.batch();
    for (int i = 0; i < missing.length; i++) {
      batch.update(missing[i].reference, {
        'sortIndex': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// ✅ 근무자 순서 재정렬
  Future<void> reorderWorkers({
    required String ownerUid,
    required String storeId,
    required List<StoreWorker> ordered,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty) return;
    if (ordered.isEmpty) return;

    final batch = _db.batch();
    for (int i = 0; i < ordered.length; i++) {
      final w = ordered[i];
      final ref =
          _workersRef(ownerUid: ownerUid, storeId: storeId).doc(w.workerUid);

      batch.update(ref, {
        'sortIndex': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// ✅ 근무자 내보내기 2단계
  Future<void> exportWorkerStep({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    required int step,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty || workerUid.isEmpty) return;

    final ref =
        _workersRef(ownerUid: ownerUid, storeId: storeId).doc(workerUid);
    final nowLocal = DateTime.now();

    if (step == 1) {
      await ref.set({
        'status': 'ended',
        'endedReason': 'exported',
        'endedAt': FieldValue.serverTimestamp(),
        'endedAtLocal': Timestamp.fromDate(nowLocal),
        'updatedAt': FieldValue.serverTimestamp(),
        'sortIndex': 999999,
      }, SetOptions(merge: true));
      return;
    }

    if (step == 2) {
      await ref.set({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedAtLocal': Timestamp.fromDate(nowLocal),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
  }

  /// ✅ 모든 근무자 한 번에 가져오기 (sortIndex 정렬)
  Future<List<StoreWorker>> fetchAllWorkersOnce({
    required String ownerUid,
    required String storeId,
    bool activeOnly = false,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty) return const <StoreWorker>[];

    final snap = await _workersRef(ownerUid: ownerUid, storeId: storeId)
        .orderBy('sortIndex', descending: false)
        .get();

    final all = snap.docs
        .map((d) => StoreWorker.fromJson(d.data(), docId: d.id))
        .toList(growable: false);

    if (!activeOnly) return all;
    return all.where((w) => w.isActive).toList(growable: false);
  }

  // ═══════════════════════════════════════════════
  // 📅 SCHEDULE 추가 메서드들 (Owner 전용)
  // ═══════════════════════════════════════════════

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ✅ 매장 전체 스케줄 실시간 구독 (최근 N일)
  Stream<List<StoreSchedule>> watchRecentSchedulesForStore({
    required String ownerUid,
    required String storeId,
    int recentDays = 120,
  }) {
    if (ownerUid.isEmpty || storeId.isEmpty) {
      return const Stream<List<StoreSchedule>>.empty();
    }

    final now = DateTime.now();
    final start = _startOfDay(now).subtract(
      Duration(days: (recentDays <= 0 ? 1 : recentDays) - 1),
    );
    final startKey = _dateKey(start.year, start.month, start.day);

    return _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map(
            (qs) => qs.docs.map(StoreSchedule.fromDoc).toList(growable: false));
  }

  /// ✅ 특정 근무자 스케줄 read-only 구독
  Stream<List<StoreSchedule>> watchSchedulesForWorkerReadOnly({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    int recentDays = 365,
  }) {
    if (ownerUid.isEmpty || storeId.isEmpty || workerUid.isEmpty) {
      return const Stream<List<StoreSchedule>>.empty();
    }

    final now = DateTime.now();
    final start = _startOfDay(now).subtract(
      Duration(days: (recentDays <= 0 ? 1 : recentDays) - 1),
    );
    final startKey = _dateKey(start.year, start.month, start.day);

    return _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
        .where('workerUid', isEqualTo: workerUid)
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map(
            (qs) => qs.docs.map(StoreSchedule.fromDoc).toList(growable: false));
  }

  /// ✅ 기간 조회 (급여 계산용)
  Future<List<StoreSchedule>> fetchSchedulesForStoreInRange({
    required String ownerUid,
    required String storeId,
    required DateTime startInclusive,
    required DateTime endInclusive,
    int pageSize = 800,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty) return const <StoreSchedule>[];

    final start = _startOfDay(startInclusive);
    final end = _startOfDay(endInclusive);

    final startKey = _dateKey(start.year, start.month, start.day);
    final endKey = _dateKey(end.year, end.month, end.day);

    Query<Map<String, dynamic>> base =
        _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .where('dateKey', isLessThanOrEqualTo: endKey)
            .orderBy('dateKey', descending: false)
            .orderBy('startMin', descending: false);

    final out = <StoreSchedule>[];
    DocumentSnapshot<Map<String, dynamic>>? last;

    while (true) {
      Query<Map<String, dynamic>> q = base.limit(pageSize);
      if (last != null) q = q.startAfterDocument(last);

      final snap = await q.get();
      if (snap.docs.isEmpty) break;

      out.addAll(snap.docs.map(StoreSchedule.fromDoc));
      last = snap.docs.last;

      if (snap.docs.length < pageSize) break;
    }

    return out;
  }

  // ═══════════════════════════════════════════════
  // 🏠 PERSONAL ALBA (개인 알바)
  // ═══════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _myAlbasRef(String uid) =>
      _db.collection('users').doc(uid).collection('myAlbas');

  /// ✅ 개인 알바 목록 구독
  Stream<List<UICalendarAlba>> watchMyPersonalAlbas(String uid) {
    return _myAlbasRef(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map((doc) {
              final d = doc.data();
              return UICalendarAlba(
                id: doc.id,
                storeId: '',
                name: (d['name'] as String?) ?? '개인 알바',
                hourlyWage: (d['hourlyWage'] as num?)?.toInt() ?? 0,
                colorHex: (d['colorHex'] as String?) ?? '#3B82F6',
                payDay: (d['payDay'] as num?)?.toInt() ?? 25,
              );
            }).toList(growable: false));
  }

  /// ✅ 개인 알바 정책 스트림 (albaId → policy map)
  /// 앱 재시작 후 정책 복원에 사용
  /// 개인 알바 정책 + policyHistory 구독
  Stream<Map<String, Map<String, dynamic>>> watchMyPersonalAlbaPolicies(
      String uid) {
    return _myAlbasRef(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((qs) {
      final result = <String, Map<String, dynamic>>{};
      for (final doc in qs.docs) {
        final d = doc.data();
        final policy = (d['policy'] as Map?)?.cast<String, dynamic>();
        if (policy != null && policy.isNotEmpty) {
          // ✅ policyHistory도 함께 전달
          final merged = Map<String, dynamic>.from(policy);
          final hist = d['policyHistory'];
          if (hist != null) merged['_policyHistory'] = hist;
          result[doc.id] = merged;
        }
      }
      return result;
    });
  }

  /// ✅ 개인 알바 추가
  Future<String> addPersonalAlba({
    required String uid,
    required String name,
    required int hourlyWage,
    required String colorHex,
    required int payDay,
    Map<String, dynamic>? policy, // ✅ 세금·보험·수당 정책
  }) async {
    final today = DateTime.now();
    final todayStr = '1970-01-01'; // 초기 밴드: 처음부터 이 시급 적용
    final initialHist = <Map<String, dynamic>>[
      {
        'hourlyWage': hourlyWage,
        'effectiveFrom': todayStr,
        if (policy != null) ...policy,
      }
    ];
    final doc = await _myAlbasRef(uid).add({
      'name': name,
      'hourlyWage': hourlyWage,
      'colorHex': colorHex,
      'payDay': payDay,
      if (policy != null) 'policy': policy,
      'policyHistory': initialHist,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// ✅ 개인 알바 삭제
  Future<void> deletePersonalAlba({
    required String uid,
    required String albaId,
  }) async {
    await _myAlbasRef(uid).doc(albaId).delete();
  }

  /// ✅ 개인 알바 기본 정보 수정
  Future<void> updatePersonalAlba({
    required String uid,
    required String albaId,
    required String name,
    required int hourlyWage,
    required String colorHex,
    required int payDay,
  }) async {
    await _myAlbasRef(uid).doc(albaId).update({
      'name': name,
      'hourlyWage': hourlyWage,
      'colorHex': colorHex,
      'payDay': payDay,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ✅ 개인 알바 정책까지 함께 저장 (세금·보험·수당·급여주기)
  Future<void> updatePersonalAlbaWithPolicy({
    required String uid,
    required String albaId,
    required String name,
    required int hourlyWage,
    int? previousHourlyWage, // ✅ 변경 전 시급 (이력 저장용)
    required String colorHex,
    required int payDay,
    Map<String, dynamic>? policy, // null이면 정책 미변경
    DateTime? policyEffectiveFrom, // ✅ 정책 적용 시작일 (null=오늘)
    DateTime? wageEffectiveFrom, // ✅ 시급 적용 시작일 (null=오늘)
  }) async {
    final today = DateTime.now();
    // 시급/정책 날짜 분리
    final wageDateEff = wageEffectiveFrom ?? today;
    final wageDateStr =
        _dateKey(wageDateEff.year, wageDateEff.month, wageDateEff.day);
    final policyDateEff = policyEffectiveFrom ?? today;
    final policyDateStr =
        _dateKey(policyDateEff.year, policyDateEff.month, policyDateEff.day);

    final data = <String, dynamic>{
      'name': name,
      'hourlyWage': hourlyWage,
      'colorHex': colorHex,
      'payDay': payDay,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // ✅ 정책·시급 변경 이력 (날짜 분리 저장)
    if (policy != null) {
      data['policy'] = policy;
    }
    // ✅ 핵심: 이전 시급을 "1970-01-01" 초기 밴드로 명시 저장
    final histEntries = <Map<String, dynamic>>[];

    if (previousHourlyWage != null) {
      // ① 이전 시급 초기 밴드
      histEntries.add(
          {'hourlyWage': previousHourlyWage, 'effectiveFrom': '1970-01-01'});
      // ② 새 시급 밴드
      histEntries.add({
        'hourlyWage': hourlyWage,
        'effectiveFrom': wageDateStr,
      });
    } else {
      // 최초 등록
      histEntries.add({
        'hourlyWage': hourlyWage,
        'effectiveFrom': '1970-01-01',
      });
    }

    if (policy != null) {
      // ③ 정책 밴드
      histEntries.add({
        ...policy,
        'hourlyWage': hourlyWage,
        'effectiveFrom': policyDateStr,
      });
    }
    if (histEntries.isNotEmpty) {
      data['policyHistory'] = FieldValue.arrayUnion(histEntries);
    }
    await _myAlbasRef(uid).doc(albaId).set(data, SetOptions(merge: true));
  }

  /// ✅ Join 알바 시급만 업데이트 (알바생이 직접 변경 가능한 유일한 항목)
  Future<void> updateJoinAlbaWage({
    required String uid,
    required String ownerUid,
    required String storeId,
    required int hourlyWage,
  }) async {
    await _myStoreJoinDoc(
      myUid: uid,
      ownerUid: ownerUid,
      storeId: storeId,
    ).set({
      'hourlyWage': hourlyWage,
      'defaultHourlyWage': hourlyWage,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ═══════════════════════════════════════════════
  // 🔗 STORE JOINS (매장 조인 관리)
  // ═══════════════════════════════════════════════

  bool _isActiveJoin(Map<String, dynamic> m) {
    final s = (m['status'] as String?)?.trim().toLowerCase();
    return (s == null || s.isEmpty || s == 'active');
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  /// ✅ 활성 조인 경로 구독 (스케줄 구독용)
  Stream<List<ActiveJoinPath>> watchActiveJoinPaths(String uid) {
    return _myStoreJoinsRef(uid).snapshots().map((snap) {
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

      out.sort((a, b) {
        final t = a.ownerUid.compareTo(b.ownerUid);
        if (t != 0) return t;
        return a.storeId.compareTo(b.storeId);
      });

      return out;
    });
  }

  /// ✅ 조인 매장 목록 구독 (홈 화면용)
  Stream<List<UICalendarAlba>> watchMyAlbas(String uid) {
    return _myStoreJoinsRef(uid).snapshots().map((snap) {
      final items = <({UICalendarAlba alba, DateTime recent})>[];

      for (final d in snap.docs) {
        final m = d.data();

        if (!_isActiveJoin(m)) continue;

        final storeId = ((m['storeId'] as String?) ?? d.id).trim();
        if (storeId.isEmpty) continue;

        final alias = (m['storeAliasName'] as String?)?.trim();
        final storeName = (m['storeName'] as String?)?.trim();
        final name = (alias != null && alias.isNotEmpty)
            ? alias
            : ((storeName != null && storeName.isNotEmpty) ? storeName : '매장');

        final colorHex = (m['colorHex'] as String?) ?? '#3B82F6';
        // ✅ ownerSetting 우선 (사장님이 설정한 값 → 사장님 storeJoins 동기화)
        final ownerSetting =
            (m['ownerSetting'] as Map?)?.cast<String, dynamic>();
        final wage = _toInt(ownerSetting?['hourlyWage']) ??
            _toInt(m['defaultHourlyWage']) ??
            _toInt(m['hourlyWage']) ??
            0;
        final payDay =
            (_toInt(ownerSetting?['payDay']) ?? _toInt(m['payDay']) ?? 25)
                .clamp(1, 31);

        items.add((
          alba: UICalendarAlba(
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

      items.sort((a, b) {
        final t = b.recent.compareTo(a.recent);
        if (t != 0) return t;
        return a.alba.name.compareTo(b.alba.name);
      });

      return items.map((e) => e.alba).toList();
    });
  }

  /// ✅ 매장 기본 설정 스냅샷 구독
  Stream<Map<String, AlbaStoreDefaultsSnapshot>> watchMyStoreDefaults(
      String uid) {
    return _myStoreJoinsRef(uid).snapshots().map((snap) {
      final map = <String, AlbaStoreDefaultsSnapshot>{};

      for (final d in snap.docs) {
        final m = d.data();

        if (!_isActiveJoin(m)) continue;

        final storeId = ((m['storeId'] as String?) ?? d.id).trim();
        if (storeId.isEmpty) continue;

        // ✅ ownerSetting 우선 (사장님 설정 실시간 반영)
        final ownerSettingDef =
            (m['ownerSetting'] as Map?)?.cast<String, dynamic>();
        final payDay =
            (_toInt(ownerSettingDef?['payDay']) ?? _toInt(m['payDay']) ?? 25)
                .clamp(1, 31);
        final hourlyWage = _toInt(ownerSettingDef?['hourlyWage']) ??
            _toInt(m['defaultHourlyWage']) ??
            _toInt(m['hourlyWage']) ??
            0;

        final policy =
            (ownerSettingDef?['policy'] as Map?)?.cast<String, dynamic>() ??
                (m['policy'] as Map?)?.cast<String, dynamic>();

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

        final rawHist = m['policyHistory'];
        final hist = PolicyHistory.fromList(rawHist);

        map[storeId] = AlbaStoreDefaultsSnapshot(
          hourlyWage: hourlyWage,
          tax: tax,
          insurance: ins,
          surcharge: sur,
          payrollPolicy: payroll,
          payDay: payDay,
          policyHistory: hist.isNotEmpty ? hist : null,
        );
      }

      return map;
    });
  }
}
