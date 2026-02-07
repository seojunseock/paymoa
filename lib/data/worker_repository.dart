// lib/data/worker_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/store.dart';
import '../models/store_worker.dart';
import 'store_repository.dart';

class WorkerRepository {
  WorkerRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storeRepo = StoreRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final StoreRepository _storeRepo;

  // ─────────────────────────────────────────────
  // paths
  // ─────────────────────────────────────────────

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

  /// ✅ storeJoins 문서 id는 "ownerUid_storeId" 로 통일 (장기 안정)
  String joinIdOf(String ownerUid, String storeId) => '${ownerUid}_$storeId';

  DocumentReference<Map<String, dynamic>> _myStoreJoinDoc({
    required String myUid,
    required String ownerUid,
    required String storeId,
  }) =>
      _myStoreJoinsRef(myUid).doc(joinIdOf(ownerUid, storeId));

  // ─────────────────────────────────────────────
  // ✅ 사장님: 근무자 목록 스트림
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // ✅ 사장님: 근무자 설정 저장
  // ─────────────────────────────────────────────
  Future<void> saveWorkerSettings({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String? displayName,
    required bool inheritFromStore,
    int? hourlyWage,
    int? payDay,
    Map<String, dynamic>? policyOverride,
  }) async {
    final nowServer = FieldValue.serverTimestamp();

    // 1) owner workers/{workerUid}
    await _workerDoc(ownerUid: ownerUid, storeId: storeId, workerUid: workerUid)
        .set({
      'workerUid': workerUid,
      if (displayName != null) 'displayName': displayName,
      'inheritFromStore': inheritFromStore,
      if (hourlyWage != null) 'hourlyWage': hourlyWage,
      if (payDay != null) 'payDay': payDay,
      if (policyOverride != null) 'policyOverride': policyOverride,
      'updatedAt': nowServer,
    }, SetOptions(merge: true));

    // 2) worker storeJoins 동기화
    try {
      await _myStoreJoinDoc(
        myUid: workerUid,
        ownerUid: ownerUid,
        storeId: storeId,
      ).set({
        'inheritFromStore': inheritFromStore,
        if (hourlyWage != null) ...{
          'hourlyWage': hourlyWage,
          'defaultHourlyWage': hourlyWage,
        },
        if (payDay != null) 'payDay': payDay,
        if (policyOverride != null) 'policy': policyOverride,
        'updatedAt': nowServer,
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  // ─────────────────────────────────────────────
  // ✅ (핵심) 사장님: 근무자 내보내기(종료 처리)
  // = 삭제 ❌ / ended ✅
  // ─────────────────────────────────────────────
  Future<void> endWorker({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String reason = 'kicked',
  }) async {
    final nowLocal = DateTime.now();
    final nowServer = FieldValue.serverTimestamp();

    // owner workers/{workerUid}
    await _workerDoc(ownerUid: ownerUid, storeId: storeId, workerUid: workerUid)
        .set({
      'status': 'ended',
      'endedReason': reason,
      'endedAt': nowServer,
      'endedAtLocal': Timestamp.fromDate(nowLocal),
      'updatedAt': nowServer,
    }, SetOptions(merge: true));

    // worker storeJoins/{ownerUid_storeId}
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

  // ✅ 호환용: 화면에서 endworker(...)로 잘못 호출해도 안 터지게
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

  // ✅ 호환: 기존 코드 removeWorker() -> endWorker()
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

  // ─────────────────────────────────────────────
  // ✅ 알바생: 코드 입력 joinByCode()
  // (너가 쓰는 AppShell 방식이 따로 있어서, 이건 그대로 둬도 됨)
  // ─────────────────────────────────────────────
  Future<Store?> joinByCode({
    required String code,
    required bool applyDefaults,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');

    final normalized = code.trim().toUpperCase().replaceAll(' ', '');
    final ref = await _storeRepo.resolveJoinRefByCode(normalized);
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

    final store = await _storeRepo.fetchStoreByJoinRef(ref);
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
}
