// lib/data/owner_worker_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store_worker.dart';

class OwnerWorkerRepository {
  OwnerWorkerRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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

  // ─────────────────────────────────────────
  // WATCH: 근무자 목록 (정렬 포함)
  // ✅ Firestore에서는 sortIndex만 정렬하고
  //    activeOnly 필터는 "클라에서" 거는 방식(인덱스/쿼리 복잡도 ↓)
  // ─────────────────────────────────────────
  Stream<List<StoreWorker>> watchWorkers({
    required String ownerUid,
    required String storeId,
    bool activeOnly = false, // 기본 false: (문서/정산 등) 전체 필요할 때가 많음
  }) {
    if (ownerUid.isEmpty || storeId.isEmpty) {
      return const Stream<List<StoreWorker>>.empty();
    }

    return _workersRef(ownerUid: ownerUid, storeId: storeId)
        .orderBy('sortIndex', descending: false)
        .snapshots()
        .map((qs) {
      final all = qs.docs
          .map((d) => StoreWorker.fromJson(d.data(), docId: d.id))
          .toList(growable: false);

      if (!activeOnly) return all;

      final filtered = all.where((w) => w.isActive).toList(growable: false);
      return filtered;
    });
  }

  // ─────────────────────────────────────────
  // ONCE: 근무자 목록 1회 가져오기
  // ─────────────────────────────────────────
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

  // ─────────────────────────────────────────
  // 레거시 보정: sortIndex 없으면 채워넣기
  // ─────────────────────────────────────────
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

  // ─────────────────────────────────────────
  // ReorderableListView 결과 저장
  // ordered: UI에서 이미 순서대로 정렬된 리스트
  // ─────────────────────────────────────────
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

  // ─────────────────────────────────────────
  // ✅ 내보내기(퇴사/종료) 처리
  // - 삭제 X
  // - status = 'ended'
  // - endedAt 기록
  // - (선택) sortIndex를 뒤로 밀어 active 정렬에 섞이지 않게
  // ─────────────────────────────────────────
  Future<void> endWorker({
    required String ownerUid,
    required String storeId,
    required String workerUid,
    String reason = 'kicked', // kicked/left 등
  }) async {
    if (ownerUid.isEmpty || storeId.isEmpty || workerUid.isEmpty) return;

    final nowLocal = DateTime.now();

    await _workersRef(ownerUid: ownerUid, storeId: storeId).doc(workerUid).set({
      'status': 'ended',
      'endedReason': reason,
      'endedAt': FieldValue.serverTimestamp(),
      'endedAtLocal': Timestamp.fromDate(nowLocal),
      'updatedAt': FieldValue.serverTimestamp(),

      // ✅ active 리스트 정렬 섞임 방지(선택)
      // sortIndex를 큰 값으로 보내면 active 정렬이 더 깔끔해짐
      'sortIndex': 999999,
    }, SetOptions(merge: true));
  }
}
