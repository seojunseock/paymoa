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
import '../payroll/payroll_document_service.dart';

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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ✅ 날짜 키 생성 (정렬용)
  int _dateKey(int y, int m, int d) => (y * 10000 + m * 100 + d);

  /// ✅ 날짜 문자열 생성 (policyHistory effectiveFrom용) 'YYYY-MM-DD'
  String _ymdStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ✅ 최근 키 계산 (정렬용)
  DateTime _recentKey(Map<String, dynamic> m) {
    final u = _tsToDate(m['updatedAt']);
    if (u.millisecondsSinceEpoch != 0) return u;

    final c = _tsToDate(m['createdAt']);
    if (c.millisecondsSinceEpoch != 0) return c;

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _hasPolicyHistory(dynamic raw) => raw is List && raw.isNotEmpty;

  Map<String, dynamic> _mergeHistoryEntryMaps(
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

  List<Map<String, dynamic>> _mergeHistoryEntriesByEffectiveFrom(
    List<Map<String, dynamic>> entries,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    final order = <String>[];

    for (final raw in entries) {
      final e = Map<String, dynamic>.from(raw);
      final effectiveFrom = (e['effectiveFrom'] ?? '').toString().trim();
      if (effectiveFrom.isEmpty) continue;

      if (!merged.containsKey(effectiveFrom)) {
        merged[effectiveFrom] = e;
        order.add(effectiveFrom);
      } else {
        merged[effectiveFrom] =
            _mergeHistoryEntryMaps(merged[effectiveFrom]!, e);
      }
    }

    return order.map((k) => merged[k]!).toList(growable: false);
  }

  List<Map<String, dynamic>> _buildHistoryEntries({
    required dynamic existingHistoryRaw,
    Map<String, dynamic>? baseline,
    Map<String, dynamic>? changed,
  }) {
    final out = <Map<String, dynamic>>[];

    final hasExisting = _hasPolicyHistory(existingHistoryRaw);
    if (!hasExisting && baseline != null && baseline.isNotEmpty) {
      out.add(Map<String, dynamic>.from(baseline));
    }

    if (changed != null && changed.isNotEmpty) {
      out.add(Map<String, dynamic>.from(changed));
    }

    return _mergeHistoryEntriesByEffectiveFrom(out);
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
    DateTime? effectiveFrom,
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

    final effectiveDate = _dateOnly(effectiveFrom ?? DateTime.now());
    final effectiveDateStr = _ymdStr(effectiveDate);

    // ✅ 매장 정책 변경 이력 저장 (매장 doc에도)
    if (policy != null || defaultHourlyWage != null) {
      Map<String, dynamic>? baseline;
      final existingStorePH = current['policyHistory'];
      if (!_hasPolicyHistory(existingStorePH)) {
        final oldPolicy = current['policy'];
        if (oldPolicy is Map) {
          baseline = {
            ...oldPolicy.cast<String, dynamic>(),
            'effectiveFrom': '1970-01-01',
          };
        }
      }

      final histEntries = _buildHistoryEntries(
        existingHistoryRaw: existingStorePH,
        baseline: baseline,
        changed: {
          if (policy != null) ...policy,
          if (defaultHourlyWage != null) 'hourlyWage': defaultHourlyWage,
          'effectiveFrom': effectiveDateStr,
        },
      );

      if (histEntries.isNotEmpty) {
        final existingList = (existingStorePH is List)
            ? existingStorePH
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];
        final fullHistory = _mergeHistoryEntriesByEffectiveFrom(
            [...existingList, ...histEntries]);
        await storeDoc.set(
          {'policyHistory': fullHistory},
          SetOptions(merge: true),
        );
      }
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
      colorHex: colorHex,
      previousWage: previousWage,
      effectiveFrom: effectiveDate,
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
    String? colorHex, // ✅ 매장 색상 전파
    int? previousWage, // ✅ 변경 전 시급 (과거 스케줄 고정용)
    DateTime? effectiveFrom, // ✅ 실제 적용 시작일 (null=오늘)
  }) {
    if (defaultHourlyWage == null &&
        payDay == null &&
        policy == null &&
        colorHex == null) {
      return;
    }

    Future.microtask(() async {
      try {
        final baseDate = _dateOnly(effectiveFrom ?? DateTime.now());

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
            // ✅ 시급이 바뀐 경우: 기준일 이전 스케줄에 기존 시급 고정
            if (defaultHourlyWage != null &&
                previousWage != null &&
                defaultHourlyWage != previousWage) {
              final untilKey =
                  _dateKey(baseDate.year, baseDate.month, baseDate.day);
              final pastSnap = await _storeSchedulesRef(
                ownerUid: ownerUid,
                storeId: storeId,
              )
                  .where('workerUid', isEqualTo: workerUid)
                  .where('dateKey', isLessThan: untilKey)
                  .get();

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
                      SetOptions(merge: true),
                    );
                  }
                  await b.commit();
                }
                debugPrint(
                    '[propagate] ✓ $workerUid 과거 스케줄 시급 고정 (${previousWage}원)');
              }

              // ✅ 기준일 포함 이후 스케줄에 새 시급 적용
              final futureKey =
                  _dateKey(baseDate.year, baseDate.month, baseDate.day);
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
                      SetOptions(merge: true),
                    );
                  }
                  await b.commit();
                }
                debugPrint(
                    '[propagate] ✓ $workerUid 기준일 이후 스케줄 새 시급 적용 (${defaultHourlyWage}원)');
              }
            }

            // ② 알바생 storeJoins 업데이트 (기존 doc ID 그대로 사용)
            final joinRef = await _resolveStoreJoinRef(
              workerUid: workerUid,
              ownerUid: ownerUid,
              storeId: storeId,
            );
            final joinSnap = await joinRef.get();
            if (!joinSnap.exists) continue;

            final ownerSettingUpdate = <String, dynamic>{
              if (defaultHourlyWage != null) 'hourlyWage': defaultHourlyWage,
              if (payDay != null) 'payDay': payDay,
              if (policy != null) 'policy': policy,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            final joinUpdates = <String, dynamic>{
              'ownerUid': ownerUid,
              'storeId': storeId,
              if (defaultHourlyWage != null) ...{
                'hourlyWage': defaultHourlyWage,
                'defaultHourlyWage': defaultHourlyWage,
              },
              if (payDay != null) 'payDay': payDay,
              if (policy != null) 'policy': policy,
              if (colorHex != null) 'colorHex': colorHex,
              'ownerSetting': ownerSettingUpdate,
              'updatedAt': FieldValue.serverTimestamp(),
            };

            if (policy != null || defaultHourlyWage != null) {
              final effectiveDateOnly =
                  _dateOnly(effectiveFrom ?? DateTime.now());
              final effectiveDateStr = _ymdStr(effectiveDateOnly);

              Map<String, dynamic>? baseline;
              final joinData = joinSnap.data() ?? {};
              final existingJoinPH = joinData['policyHistory'];
              if (!_hasPolicyHistory(existingJoinPH)) {
                final oldPolicy = joinData['policy'];
                if (oldPolicy is Map) {
                  baseline = {
                    ...oldPolicy.cast<String, dynamic>(),
                    if (previousWage != null) 'hourlyWage': previousWage,
                    'effectiveFrom': '1970-01-01',
                  };
                }
              }

              final histEntries = _buildHistoryEntries(
                existingHistoryRaw: joinData['policyHistory'],
                baseline: baseline,
                changed: {
                  if (policy != null) ...policy,
                  if (defaultHourlyWage != null)
                    'hourlyWage': defaultHourlyWage,
                  if (previousWage != null) 'previousHourlyWage': previousWage,
                  'effectiveFrom': effectiveDateStr,
                },
              );

              if (histEntries.isNotEmpty) {
                final existingList = (existingJoinPH is List)
                    ? existingJoinPH
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList()
                    : <Map<String, dynamic>>[];
                final fullHistory = _mergeHistoryEntriesByEffectiveFrom(
                    [...existingList, ...histEntries]);
                await joinRef.set(
                  {'policyHistory': fullHistory},
                  SetOptions(merge: true),
                );
              }
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

    await _storesRef(id).doc(sid).delete();

    final code = storeCode?.trim();
    if (code != null && code.isNotEmpty) {
      try {
        await _joinCodesRef.doc(code).delete();
      } catch (e) {
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
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
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

    return q.orderBy('joinedAt', descending: false).snapshots().map((snap) {
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
    int? previousHourlyWage,
    int? payDay,
    Map<String, dynamic>? policyOverride,
    DateTime? effectiveFrom,
    DateTime? policyEffectiveFrom,
    DateTime? surchargeEffectiveFrom, // ✅ 가산정책 전용 적용일 (세금/보험과 날짜 분리)
    Map<String, dynamic>? previousPolicyOverride,
  }) async {
    final nowServer = FieldValue.serverTimestamp();

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    String toYmd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final wageDate = effectiveFrom == null
        ? todayDate
        : DateTime(
            effectiveFrom.year,
            effectiveFrom.month,
            effectiveFrom.day,
          );
    final wageDateStr = toYmd(wageDate);

    final policyDate = policyEffectiveFrom == null
        ? todayDate
        : DateTime(
            policyEffectiveFrom.year,
            policyEffectiveFrom.month,
            policyEffectiveFrom.day,
          );
    final policyDateStr = toYmd(policyDate);

    final wageIsNow = !wageDate.isAfter(todayDate);
    final policyIsNow = !policyDate.isAfter(todayDate);

    // 기존 policyHistory 읽기 (worker doc)
    final workerDocRef = _workerDoc(
        ownerUid: ownerUid, storeId: storeId, workerUid: workerUid);
    final workerSnap = await workerDocRef.get();
    final existingWorkerHistoryRaw =
        (workerSnap.data() ?? <String, dynamic>{})['policyHistory'];

    Map<String, dynamic>? baseline;
    if (!_hasPolicyHistory(existingWorkerHistoryRaw)) {
      if (hourlyWage != null && previousHourlyWage != null) {
        baseline = {
          if (previousPolicyOverride != null) ...previousPolicyOverride,
          'hourlyWage': previousHourlyWage,
          'effectiveFrom': '1970-01-01',
        };
      } else if (hourlyWage != null && previousHourlyWage == null) {
        baseline = {
          if (previousPolicyOverride != null) ...previousPolicyOverride,
          'hourlyWage': hourlyWage,
          'effectiveFrom': '1970-01-01',
        };
      }
    }

    final changed = <String, dynamic>{
      if (policyOverride != null) ...policyOverride,
      if (hourlyWage != null) 'hourlyWage': hourlyWage,
      'effectiveFrom': policyOverride != null ? policyDateStr : wageDateStr,
    };

    // ✅ 가산정책 전용 날짜가 따로 있으면 surcharge-only 엔트리 추가 생성
    // (세금/보험은 다음 달, 가산정책은 오늘 → 두 날짜가 다를 때만)
    Map<String, dynamic>? surchargeOnlyEntry;
    if (surchargeEffectiveFrom != null &&
        policyOverride != null &&
        policyOverride['surcharge'] != null) {
      final surchargeDate = DateTime(
        surchargeEffectiveFrom.year,
        surchargeEffectiveFrom.month,
        surchargeEffectiveFrom.day,
      );
      final surchargeDateStr = toYmd(surchargeDate);
      if (surchargeDateStr != policyDateStr) {
        surchargeOnlyEntry = {
          'surcharge': policyOverride['surcharge'],
          'effectiveFrom': surchargeDateStr,
        };
      }
    }

    var histEntries = _buildHistoryEntries(
      existingHistoryRaw: existingWorkerHistoryRaw,
      baseline: baseline,
      changed: changed.isNotEmpty ? changed : null,
    );
    if (surchargeOnlyEntry != null) {
      // surcharge-only 엔트리를 기존 new-entries 목록에 추가해서 날짜 순 병합
      // (existingList는 _buildFullHistory에서 나중에 합쳐짐)
      histEntries = _mergeHistoryEntriesByEffectiveFrom(
          [...histEntries, surchargeOnlyEntry]);
    }

    List<Map<String, dynamic>> _buildFullHistory(dynamic existingRaw) {
      final existingList = (existingRaw is List)
          ? existingRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];
      return _mergeHistoryEntriesByEffectiveFrom(
          [...existingList, ...histEntries]);
    }

    final workerFullHistory = _buildFullHistory(existingWorkerHistoryRaw);

    await workerDocRef.set({
      'workerUid': workerUid,
      if (displayName != null) 'displayName': displayName,
      'inheritFromStore': inheritFromStore,
      if (hourlyWage != null && wageIsNow) 'hourlyWage': hourlyWage,
      if (payDay != null) 'payDay': payDay,
      if (policyOverride != null && policyIsNow)
        'policyOverride': policyOverride,
      if (workerFullHistory.isNotEmpty) 'policyHistory': workerFullHistory,
      'updatedAt': nowServer,
      if (effectiveFrom != null) 'effectiveFrom': Timestamp.fromDate(wageDate),
      if (policyEffectiveFrom != null)
        'policyEffectiveFrom': Timestamp.fromDate(policyDate),
    }, SetOptions(merge: true));

    try {
      final joinRef = await _resolveStoreJoinRef(
        workerUid: workerUid,
        ownerUid: ownerUid,
        storeId: storeId,
      );

      final joinSnap = await joinRef.get();
      final existingJoinHistoryRaw =
          (joinSnap.data() ?? <String, dynamic>{})['policyHistory'];
      final joinFullHistory = _buildFullHistory(existingJoinHistoryRaw);

      await joinRef.set({
        'ownerUid': ownerUid,
        'storeId': storeId,
        'inheritFromStore': inheritFromStore,
        if (hourlyWage != null && wageIsNow) ...{
          'hourlyWage': hourlyWage,
          'defaultHourlyWage': hourlyWage,
        },
        if (payDay != null) 'payDay': payDay,
        if (policyOverride != null && policyIsNow) 'policy': policyOverride,
        if (joinFullHistory.isNotEmpty) 'policyHistory': joinFullHistory,
        'ownerSetting': {
          'inheritFromStore': inheritFromStore,
          if (hourlyWage != null && wageIsNow) 'hourlyWage': hourlyWage,
          if (payDay != null) 'payDay': payDay,
          if (policyOverride != null && policyIsNow) 'policy': policyOverride,
          if (effectiveFrom != null)
            'effectiveFrom': Timestamp.fromDate(wageDate),
          if (policyEffectiveFrom != null)
            'policyEffectiveFrom': Timestamp.fromDate(policyDate),
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
  /// recentDays = 0 → 전체 기간 (제한 없음)
  Stream<List<UICalendarSchedule>> watchMyPersonalSchedulesUiRecentDays({
    required String workerUid,
    int recentDays = 0,
  }) {
    if (workerUid.isEmpty) {
      return const Stream<List<UICalendarSchedule>>.empty();
    }

    Query<Map<String, dynamic>> q;
    if (recentDays > 0) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: recentDays - 1));
      final startKey = _dateKey(start.year, start.month, start.day);
      q = _mySchedulesRef(workerUid)
          .where('dateKey', isGreaterThanOrEqualTo: startKey)
          .orderBy('dateKey', descending: false);
    } else {
      q = _mySchedulesRef(workerUid).orderBy('dateKey', descending: false);
    }

    return q.snapshots().map((qs) {
      final items = qs.docs.map(_uiFromPersonalDoc).toList();
      items.sort((a, b) {
        final da = a.year * 10000 + a.month * 100 + a.day;
        final db = b.year * 10000 + b.month * 100 + b.day;
        if (da != db) return da.compareTo(db);
        final sa = a.startHour * 60 + a.startMinute;
        final sb = b.startHour * 60 + b.startMinute;
        return sa.compareTo(sb);
      });
      return items;
    });
  }

  /// ✅ 조인 스케줄 구독 (알바생)
  /// recentDays = 0 → 전체 기간 (제한 없음)
  Stream<List<UICalendarSchedule>> watchMyJoinSchedulesByActiveJoins({
    required String workerUid,
    required Stream<List<ActiveJoinPath>> activeJoins$,
    int recentDays = 0,
  }) {
    if (workerUid.isEmpty) {
      return const Stream<List<UICalendarSchedule>>.empty();
    }

    int? startKey;
    if (recentDays > 0) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: recentDays - 1));
      startKey = _dateKey(start.year, start.month, start.day);
    }

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

        final base =
            _storeSchedulesRef(ownerUid: j.ownerUid, storeId: j.storeId)
                .where('workerUid', isEqualTo: workerUid);
        final q = startKey != null
            ? base
                .where('dateKey', isGreaterThanOrEqualTo: startKey)
                .orderBy('dateKey', descending: false)
            : base.orderBy('dateKey', descending: false);

        perStoreSubs[key] = q.snapshots().listen((qs) {
          final items = qs.docs.map(_uiFromJoinGroupDoc).toList();
          items.sort((a, b) {
            final da = a.year * 10000 + a.month * 100 + a.day;
            final db = b.year * 10000 + b.month * 100 + b.day;
            if (da != db) return da.compareTo(db);
            final sa = a.startHour * 60 + a.startMinute;
            final sb = b.startHour * 60 + b.startMinute;
            return sa.compareTo(sb);
          });
          latestByStore[key] = items;
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
  /// recentDays = 0 → 전체 기간 (제한 없음)
  Stream<List<UICalendarSchedule>> watchMySchedulesUiMergedV2({
    required String workerUid,
    required Stream<List<ActiveJoinPath>> activeJoins$,
    int recentDays = 0,
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
      'wageMultiplier': ui.wageMultiplier == 1.0 ? null : ui.wageMultiplier,
      'dateKey': dateKey,
      'startMin': startMin,
      'updatedAt': FieldValue.serverTimestamp(),
    };

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
      'wageMultiplier': ui.wageMultiplier == 1.0 ? null : ui.wageMultiplier,
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
  Future<void> bulkUpdateScheduleWage({
    required String workerUid,
    required String albaId,
    required int newWage,
    required List<UICalendarSchedule> schedules,
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

    if (untilDate != null) {
      final untilKey = _dateKey(untilDate.year, untilDate.month, untilDate.day);
      final fromKey = fromDate != null
          ? _dateKey(fromDate.year, fromDate.month, fromDate.day)
          : null;

      var q = _mySchedulesRef(workerUid)
          .where('albaId', isEqualTo: albaId)
          .where('dateKey', isLessThan: untilKey);
      if (fromKey != null) {
        q = q.where('dateKey', isGreaterThanOrEqualTo: fromKey);
      }
      final personalSnap = await q.get();
      final personalDocs = personalSnap.docs.toList();

      final joinDocs = schedules
          .where((s) =>
              s.albaId == albaId && s.docPath != null && s.docPath!.isNotEmpty)
          .toList();

      final Set<String> ownerStorePairs = {};
      for (final s in joinDocs) {
        final parts = s.docPath!.split('/');
        if (parts.length >= 6) {
          ownerStorePairs.add('${parts[1]}/${parts[3]}');
        }
      }

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> allJoinDocs = [];
      for (final pair in ownerStorePairs) {
        final parts = pair.split('/');
        final ownerUid2 = parts[0], storeId2 = parts[1];
        var jq = _storeSchedulesRef(ownerUid: ownerUid2, storeId: storeId2)
            .where('workerUid', isEqualTo: workerUid)
            .where('dateKey', isLessThan: untilKey);
        if (fromKey != null) {
          jq = jq.where('dateKey', isGreaterThanOrEqualTo: fromKey);
        }
        final snap = await jq.get();
        allJoinDocs.addAll(snap.docs);
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

    if (untilDate != null) {
      final untilKey = _dateKey(untilDate.year, untilDate.month, untilDate.day);
      final fromKey = fromDate != null
          ? _dateKey(fromDate.year, fromDate.month, fromDate.day)
          : null;

      var q = _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
          .where('dateKey', isLessThan: untilKey);
      if (fromKey != null) {
        q = q.where('dateKey', isGreaterThanOrEqualTo: fromKey);
      }

      final snap = await q.get();
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
      wageMultiplier: (d['wageMultiplier'] as num?)?.toDouble() ?? 1.0,
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
      wageMultiplier: (d['wageMultiplier'] as num?)?.toDouble() ?? 1.0,
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

  /// ✅ 매장 전체 스케줄 실시간 구독
  /// recentDays = 0 → 전체 기간 (제한 없음)
  Stream<List<StoreSchedule>> watchRecentSchedulesForStore({
    required String ownerUid,
    required String storeId,
    int recentDays = 0,
  }) {
    if (ownerUid.isEmpty || storeId.isEmpty) {
      return const Stream<List<StoreSchedule>>.empty();
    }

    final ref = _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId);
    Query<Map<String, dynamic>> q;
    if (recentDays > 0) {
      final start =
          _startOfDay(DateTime.now()).subtract(Duration(days: recentDays - 1));
      final startKey = _dateKey(start.year, start.month, start.day);
      q = ref
          .where('dateKey', isGreaterThanOrEqualTo: startKey)
          .orderBy('dateKey', descending: false);
    } else {
      q = ref.orderBy('dateKey', descending: false);
    }

    return q.snapshots().map((qs) {
      final items = qs.docs.map(StoreSchedule.fromDoc).toList();
      items.sort((a, b) {
        final da = a.year * 10000 + a.month * 100 + a.day;
        final db = b.year * 10000 + b.month * 100 + b.day;
        if (da != db) return da.compareTo(db);
        final sa = a.startHour * 60 + a.startMinute;
        final sb = b.startHour * 60 + b.startMinute;
        return sa.compareTo(sb);
      });
      return items;
    });
  }

  /// ✅ 특정 근무자 스케줄 read-only 구독
  /// recentDays = 0 → 전체 기간 (제한 없음)
  Stream<List<StoreSchedule>> watchSchedulesForWorkerReadOnly({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    int recentDays = 0,
  }) {
    if (ownerUid.isEmpty || storeId.isEmpty || workerUid.isEmpty) {
      return const Stream<List<StoreSchedule>>.empty();
    }

    final base = _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
        .where('workerUid', isEqualTo: workerUid);
    Query<Map<String, dynamic>> q;
    if (recentDays > 0) {
      final start =
          _startOfDay(DateTime.now()).subtract(Duration(days: recentDays - 1));
      final startKey = _dateKey(start.year, start.month, start.day);
      q = base
          .where('dateKey', isGreaterThanOrEqualTo: startKey)
          .orderBy('dateKey', descending: false);
    } else {
      q = base.orderBy('dateKey', descending: false);
    }

    return q.snapshots().map((qs) {
      final items = qs.docs.map(StoreSchedule.fromDoc).toList();
      items.sort((a, b) {
        final da = a.year * 10000 + a.month * 100 + a.day;
        final db = b.year * 10000 + b.month * 100 + b.day;
        if (da != db) return da.compareTo(db);
        final sa = a.startHour * 60 + a.startMinute;
        final sb = b.startHour * 60 + b.startMinute;
        return sa.compareTo(sb);
      });
      return items;
    });
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

  /// ✅ 사장님 내 정보용 최근 N개월 인건비(총지급) 실시간 합산 스트림
  Stream<List<Map<String, dynamic>>> watchOwnerMonthlyGrossPoints({
    required String ownerUid,
    int months = 3,
  }) {
    if (ownerUid.trim().isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    late StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription<List<Store>>? storesSub;

    final Map<String, StreamSubscription<List<StoreWorker>>> workerSubs = {};
    final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
        scheduleSubs = {};

    final Map<String, Store> latestStores = {};
    final Map<String, List<StoreWorker>> latestWorkersByStore = {};
    final Map<String, List<StoreSchedule>> latestSchedulesByStore = {};

    DateTime dateOnlyLocal(DateTime d) => DateTime(d.year, d.month, d.day);

    List<Map<String, dynamic>> buildPoints() {
      final now = DateTime.now();
      final totals = <String, int>{};

      for (int offset = months - 1; offset >= 0; offset--) {
        final dt = DateTime(now.year, now.month - offset, 1);
        totals['${dt.year}-${dt.month}'] = 0;
      }

      for (final entry in latestStores.entries) {
        final storeId = entry.key;
        final store = entry.value;
        final workers = latestWorkersByStore[storeId] ?? const <StoreWorker>[];
        final schedules =
            latestSchedulesByStore[storeId] ?? const <StoreSchedule>[];

        // 시급 캐시: workerUid → 유효 시급
        final wageCache = <String, int>{};
        for (final w in workers) {
          final storeWage = store.defaultHourlyWage;
          wageCache[w.workerUid] = w.inheritFromStore
              ? (storeWage ?? w.hourlyWage ?? 0)
              : (w.hourlyWage ?? storeWage ?? 0);
        }

        for (final s in schedules) {
          final key = '${s.year}-${s.month}';
          if (!totals.containsKey(key)) continue;
          final wage = s.overrideHourlyWage ?? (wageCache[s.workerUid] ?? 0);
          if (wage <= 0) continue;
          final start =
              DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
          var end =
              DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          final workedMin =
              end.difference(start).inMinutes - s.breakMinutes.clamp(0, 1440);
          if (workedMin <= 0) continue;
          totals[key] = (totals[key] ?? 0) + (wage * workedMin / 60.0).round();
        }
      }

      final out = <Map<String, dynamic>>[];
      for (int offset = months - 1; offset >= 0; offset--) {
        final dt = DateTime(now.year, now.month - offset, 1);
        final key = '${dt.year}-${dt.month}';
        out.add({
          'year': dt.year,
          'month': dt.month,
          'gross': totals[key] ?? 0,
        });
      }
      return out;
    }

    Future<void> resubscribeStores(List<Store> stores) async {
      final keepIds = stores.map((e) => e.id).toSet();

      for (final store in stores) {
        latestStores[store.id] = store;

        if (!workerSubs.containsKey(store.id)) {
          workerSubs[store.id] = watchWorkers(
            ownerUid: ownerUid,
            storeId: store.id,
            activeOnly: false,
          ).listen((workers) {
            latestWorkersByStore[store.id] = workers;
            if (!controller.isClosed) {
              controller.add(buildPoints());
            }
          });
        }

        if (!scheduleSubs.containsKey(store.id)) {
          final now = DateTime.now();
          final firstMonth = DateTime(now.year, now.month - (months - 1), 1);
          final lastMonth = DateTime(now.year, now.month, 1);

          final fetchStart =
              dateOnlyLocal(firstMonth.subtract(const Duration(days: 62)));
          final fetchEnd = DateTime(lastMonth.year, lastMonth.month + 1, 0);

          final startKey =
              _dateKey(fetchStart.year, fetchStart.month, fetchStart.day);
          final endKey = _dateKey(fetchEnd.year, fetchEnd.month, fetchEnd.day);

          final q = _storeSchedulesRef(ownerUid: ownerUid, storeId: store.id)
              .where('dateKey', isGreaterThanOrEqualTo: startKey)
              .where('dateKey', isLessThanOrEqualTo: endKey)
              .orderBy('dateKey', descending: false);

          scheduleSubs[store.id] = q.snapshots().listen((snap) {
            final items = snap.docs.map(StoreSchedule.fromDoc).toList();
            items.sort((a, b) {
              final da = a.year * 10000 + a.month * 100 + a.day;
              final db = b.year * 10000 + b.month * 100 + b.day;
              if (da != db) return da.compareTo(db);
              final sa = a.startHour * 60 + a.startMinute;
              final sb = b.startHour * 60 + b.startMinute;
              return sa.compareTo(sb);
            });
            latestSchedulesByStore[store.id] = items;
            if (!controller.isClosed) {
              controller.add(buildPoints());
            }
          });
        }
      }

      final removeWorkerIds =
          workerSubs.keys.where((id) => !keepIds.contains(id)).toList();
      for (final id in removeWorkerIds) {
        await workerSubs[id]?.cancel();
        workerSubs.remove(id);
        latestWorkersByStore.remove(id);
      }

      final removeScheduleIds =
          scheduleSubs.keys.where((id) => !keepIds.contains(id)).toList();
      for (final id in removeScheduleIds) {
        await scheduleSubs[id]?.cancel();
        scheduleSubs.remove(id);
        latestSchedulesByStore.remove(id);
      }

      latestStores.removeWhere((key, value) => !keepIds.contains(key));

      if (!controller.isClosed) {
        controller.add(buildPoints());
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        storesSub = watchStores(ownerUid).listen((stores) {
          resubscribeStores(stores);
        });
      },
      onCancel: () async {
        await storesSub?.cancel();
        for (final sub in workerSubs.values) {
          await sub.cancel();
        }
        for (final sub in scheduleSubs.values) {
          await sub.cancel();
        }
        workerSubs.clear();
        scheduleSubs.clear();
        latestStores.clear();
        latestWorkersByStore.clear();
        latestSchedulesByStore.clear();
        await controller.close();
      },
    );

    return controller.stream;
  }

  /// ✅ owner 월별 인건비 그래프용 즉시 1회 조회
  Future<List<Map<String, dynamic>>> fetchOwnerMonthlyGrossPointsOnce({
    required String ownerUid,
    int months = 3,
  }) async {
    if (ownerUid.trim().isEmpty) return const <Map<String, dynamic>>[];

    final stores = await watchStores(ownerUid).first;
    final now = DateTime.now();
    final totals = <String, int>{};
    const docSvc = PayrollDocumentService();

    for (int offset = months - 1; offset >= 0; offset--) {
      final dt = DateTime(now.year, now.month - offset, 1);
      totals['${dt.year}-${dt.month}'] = 0;
    }

    for (final store in stores) {
      final workers = await watchWorkers(
        ownerUid: ownerUid,
        storeId: store.id,
        activeOnly: false,
      ).first;

      for (int offset = months - 1; offset >= 0; offset--) {
        final dt = DateTime(now.year, now.month - offset, 1);
        final key = '${dt.year}-${dt.month}';

        final monthStart = DateTime(dt.year, dt.month, 1);
        final monthEnd = DateTime(dt.year, dt.month + 1, 0);
        final fetchStart = monthStart.subtract(const Duration(days: 62));
        final fetchEnd = monthEnd;

        final schedules = await fetchSchedulesForStoreInRange(
          ownerUid: ownerUid,
          storeId: store.id,
          startInclusive: fetchStart,
          endInclusive: fetchEnd,
        );

        final rows = docSvc.buildCalendarMonthDocument(
          store: store,
          workers: workers,
          schedules: schedules,
          year: dt.year,
          month: dt.month,
        );

        int gross = 0;
        for (final row in rows) {
          gross += row.gross;
        }
        totals[key] = (totals[key] ?? 0) + gross;
      }
    }

    final out = <Map<String, dynamic>>[];
    for (int offset = months - 1; offset >= 0; offset--) {
      final dt = DateTime(now.year, now.month - offset, 1);
      final key = '${dt.year}-${dt.month}';
      out.add({
        'year': dt.year,
        'month': dt.month,
        'gross': totals[key] ?? 0,
      });
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
    Map<String, dynamic>? policy,
  }) async {
    const todayStr = '1970-01-01';
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
    int? previousHourlyWage,
    required String colorHex,
    required int payDay,
    Map<String, dynamic>? policy,
    Map<String, dynamic>? previousPolicy,
    DateTime? policyEffectiveFrom,
    DateTime? wageEffectiveFrom,
    DateTime? surchargeEffectiveFrom,
  }) async {
    final today = DateTime.now();
    final wageDateEff = _dateOnly(wageEffectiveFrom ?? today);
    final wageDateStr = _ymdStr(wageDateEff);
    final policyDateEff = _dateOnly(policyEffectiveFrom ?? today);
    final policyDateStr = _ymdStr(policyDateEff);

    final data = <String, dynamic>{
      'name': name,
      'hourlyWage': hourlyWage,
      'colorHex': colorHex,
      'payDay': payDay,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (policy != null) {
      data['policy'] = policy;
    }

    // 기존 policyHistory 읽기
    final existingDoc = await _myAlbasRef(uid).doc(albaId).get();
    final existingHistoryRaw =
        (existingDoc.data() ?? <String, dynamic>{})['policyHistory'];

    Map<String, dynamic>? baseline;
    if (!_hasPolicyHistory(existingHistoryRaw)) {
      if (previousHourlyWage != null) {
        baseline = {
          if (previousPolicy != null) ...previousPolicy,
          'hourlyWage': previousHourlyWage,
          'effectiveFrom': '1970-01-01',
        };
      } else {
        baseline = {
          if (previousPolicy != null) ...previousPolicy,
          'hourlyWage': hourlyWage,
          'effectiveFrom': '1970-01-01',
        };
      }
    }

    final changed = <String, dynamic>{
      if (policy != null) ...policy,
      'hourlyWage': hourlyWage,
      'effectiveFrom': policy != null ? policyDateStr : wageDateStr,
    };

    final histEntries = _buildHistoryEntries(
      existingHistoryRaw: existingHistoryRaw,
      baseline: baseline,
      changed: changed,
    );

    if (histEntries.isNotEmpty) {
      final existingList = (existingHistoryRaw is List)
          ? existingHistoryRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];

      // 가산정책이 세금/보험과 다른 날짜(오늘)에 적용될 때 별도 이력 항목 추가
      var allEntries = histEntries;
      if (surchargeEffectiveFrom != null && policy != null) {
        final surchargeDateStr =
            _ymdStr(_dateOnly(surchargeEffectiveFrom));
        if (surchargeDateStr != policyDateStr) {
          final surchargeOnlyEntry = <String, dynamic>{
            ...policy,
            'effectiveFrom': surchargeDateStr,
          };
          allEntries = _mergeHistoryEntriesByEffectiveFrom(
              [...histEntries, surchargeOnlyEntry]);
        }
      }

      data['policyHistory'] = _mergeHistoryEntriesByEffectiveFrom(
          [...existingList, ...allEntries]);
    }
    await _myAlbasRef(uid).doc(albaId).set(data, SetOptions(merge: true));
  }

  /// ✅ 알바생이 직접 매장을 탈퇴
  Future<void> leaveStore({
    required String workerUid,
    required String storeId,
  }) async {
    final qs = await _myStoreJoinsRef(workerUid)
        .where('storeId', isEqualTo: storeId)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return;

    final joinData = qs.docs.first.data();
    final ownerUid = joinData['ownerUid'] as String?;
    final now = DateTime.now();

    await qs.docs.first.reference.set(
      {
        'status': 'ended',
        'updatedAt': FieldValue.serverTimestamp(),
        'endedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (ownerUid != null && ownerUid.isNotEmpty) {
      try {
        await _workerDoc(
          ownerUid: ownerUid,
          storeId: storeId,
          workerUid: workerUid,
        ).set({
          'status': 'ended',
          'updatedAt': FieldValue.serverTimestamp(),
          'endedAt': FieldValue.serverTimestamp(),
          'endedAtLocal': Timestamp.fromDate(now),
          'endedReason': 'self_left',
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// ✅ 알바생 완전삭제
  Future<void> deleteWorkerCompletely({
    required String ownerUid,
    required String storeId,
    required String workerUid,
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty || workerUid.isEmpty) return;

    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    while (true) {
      Query<Map<String, dynamic>> q =
          _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId)
              .where('workerUid', isEqualTo: workerUid)
              .limit(400);
      if (lastDoc != null) q = q.startAfterDocument(lastDoc);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
      lastDoc = snap.docs.last;
    }

    await _workerDoc(
      ownerUid: ownerUid,
      storeId: storeId,
      workerUid: workerUid,
    ).delete();
  }

  /// ✅ Join 알바 시급만 업데이트
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

  /// ✅ 알바생이 join 매장 색상을 개인 설정으로 변경
  Future<void> updateJoinAlbaColorHex({
    required String workerUid,
    required String ownerUid,
    required String storeId,
    required String colorHex,
  }) async {
    final joinRef = await _resolveStoreJoinRef(
      workerUid: workerUid,
      ownerUid: ownerUid,
      storeId: storeId,
    );
    await joinRef.set({
      'colorHex': colorHex,
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

  /// ✅ 활성 조인 경로 구독
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

  /// ✅ 조인 매장 목록 구독
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
