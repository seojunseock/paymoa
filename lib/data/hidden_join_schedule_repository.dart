import 'package:cloud_firestore/cloud_firestore.dart';

class HiddenJoinScheduleRepository {
  HiddenJoinScheduleRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('hiddenJoinSchedules');

  /// 숨김 처리(조인 스케줄만)
  Future<void> hide({
    required String workerUid,
    required String scheduleId,
    required String ownerUid,
    required String storeId,
    String? employmentId,
  }) async {
    await _col(workerUid).doc(scheduleId).set({
      'scheduleId': scheduleId,
      'ownerUid': ownerUid,
      'storeId': storeId,
      if (employmentId != null) 'employmentId': employmentId,
      'hiddenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 숨김 해제(옵션)
  Future<void> unhide({
    required String workerUid,
    required String scheduleId,
  }) async {
    await _col(workerUid).doc(scheduleId).delete();
  }

  /// 숨김 목록 스트림
  Stream<Set<String>> watchHiddenIds(String workerUid) {
    return _col(workerUid).snapshots().map((snap) {
      return snap.docs.map((d) => d.id).toSet();
    });
  }
}
