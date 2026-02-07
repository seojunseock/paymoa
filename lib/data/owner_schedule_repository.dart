// lib/data/owner_schedule_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store_schedule.dart';

class OwnerScheduleRepository {
  OwnerScheduleRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _schedulesRef({
    required String ownerUid,
    required String storeId,
  }) =>
      _db
          .collection('users')
          .doc(ownerUid)
          .collection('stores')
          .doc(storeId)
          .collection('schedules');

  int _dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ✅ 매장 전체 스케줄: 최근 N일 watch
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
    final startKey = _dateKey(start);

    return _schedulesRef(ownerUid: ownerUid, storeId: storeId)
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map(
            (qs) => qs.docs.map(StoreSchedule.fromDoc).toList(growable: false));
  }

  /// ✅ 사장 화면: 근무자 1명 스케줄 read-only watch
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
    final startKey = _dateKey(start);

    return _schedulesRef(ownerUid: ownerUid, storeId: storeId)
        .where('workerUid', isEqualTo: workerUid)
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map(
            (qs) => qs.docs.map(StoreSchedule.fromDoc).toList(growable: false));
  }

  /// ✅ 기간 조회 (정산/엑셀/PDF 버튼 눌렀을 때만)
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

    final startKey = _dateKey(start);
    final endKey = _dateKey(end);

    Query<Map<String, dynamic>> base =
        _schedulesRef(ownerUid: ownerUid, storeId: storeId)
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
}
