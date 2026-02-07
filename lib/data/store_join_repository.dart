import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/alba_form_models.dart';
import '../screens/join_store_sheet.dart'; // ✅ JoinStoreSheetResult
import '../models/ui_calendar_models.dart';

class StoreJoinRepository {
  StoreJoinRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// ✅ AppShell._onJoinSubmit()과 동일 동작
  /// - users/{workerUid}/storeJoins/{storeId} 저장
  /// - users/{ownerUid}/stores/{storeId}/workers/{workerUid} 저장
  /// - users/{ownerUid}/stores/{storeId}/schedules 여러개 생성 (선택한 날짜들)
  Future<void> joinStoreAndCreateSchedules({
    required String workerUid,
    required String? workerDisplayName, // FirebaseAuth displayName
    required JoinStoreSheetResult sheet,
    required AlbaFormResult form,
  }) async {
    final store = sheet.store;
    final storeId = store.id;
    final ownerUid = store.ownerUid;

    if (workerUid.trim().isEmpty) throw StateError('workerUid empty');
    if (storeId.trim().isEmpty) throw StateError('storeId empty');
    if (ownerUid.trim().isEmpty) throw StateError('ownerUid empty');

    final db = _db;

    // ✅ storeJoins 문서 id는 storeId 유지
    final joinRef = db
        .collection('users')
        .doc(workerUid)
        .collection('storeJoins')
        .doc(storeId);

    final workerRef = db
        .collection('users')
        .doc(ownerUid)
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerUid);

    final joinSnap = await joinRef.get();
    final alreadyJoined = joinSnap.exists;

    final storePolicySnapshot =
        (store.policy ?? <String, dynamic>{}).cast<String, dynamic>();

    final inherit = form.inheritFromStore;

    final resolvedName = (inherit ? store.name : form.storeName).trim();
    final storeNameSaved = resolvedName.isEmpty ? '이름없음' : resolvedName;

    final resolvedPayDay =
        (inherit ? (store.payDay ?? form.payDay) : form.payDay).clamp(1, 31);

    final resolvedWage = inherit
        ? (store.defaultHourlyWage ?? form.hourlyWage)
        : form.hourlyWage;

    final nowServer = FieldValue.serverTimestamp();
    final nowLocal = DateTime.now();

    final joinPayload = <String, dynamic>{
      'storeId': storeId,
      'ownerUid': ownerUid,
      'storeName': storeNameSaved,
      'colorHex': inherit ? (store.colorHex ?? form.colorHex) : form.colorHex,
      'payDay': resolvedPayDay,
      'defaultHourlyWage': resolvedWage,
      'hourlyWage': resolvedWage,
      'joinedAt': alreadyJoined
          ? (joinSnap.data()?['joinedAt'] ?? nowServer)
          : nowServer,
      'inheritFromStore': inherit,
      'policy': storePolicySnapshot,
      'updatedAt': nowServer,
      if (!alreadyJoined) 'createdAt': nowServer,
      // ✅ join code 기록(나중에 디버깅/재연동에 도움)
      'code': sheet.code,
    };

    final workerPayload = <String, dynamic>{
      'workerUid': workerUid,
      'status': 'active',
      'displayName': (workerDisplayName ?? '').trim().isEmpty
          ? null
          : workerDisplayName!.trim(),
      'inheritFromStore': inherit,
      'joinedAt': nowServer,
      'updatedAt': nowServer,
    };

    final schedulesCol = db
        .collection('users')
        .doc(ownerUid)
        .collection('stores')
        .doc(storeId)
        .collection('schedules');

    final batch = db.batch();

    batch.set(joinRef, joinPayload, SetOptions(merge: true));
    batch.set(workerRef, workerPayload, SetOptions(merge: true));

    // ✅ 선택한 날짜들에 대해 store schedules 생성
    for (final dt in form.selectedDates) {
      final d = DateTime(dt.year, dt.month, dt.day);

      final dateKey = d.year * 10000 + d.month * 100 + d.day;
      final startMin = form.startHour24 * 60 + form.startMinute;

      final docRef = schedulesCol.doc();
      batch.set(docRef, <String, dynamic>{
        'workerUid': workerUid,
        // ✅ 사장 스케줄에서 albaId 자리에 storeId를 쓰는 기존 방식 유지
        'albaId': storeId,
        'year': d.year,
        'month': d.month,
        'day': d.day,
        'startHour': form.startHour24,
        'startMinute': form.startMinute,
        'endHour': form.endHour24,
        'endMinute': form.endMinute,
        'breakMinutes': form.breakMinutes,
        'workType': WorkType.basic.name,
        'overrideHourlyWage': null,
        'dateKey': dateKey,
        'startMin': startMin,
        'createdAt': nowServer,
        'updatedAt': nowServer,
        'clientCreatedAt': Timestamp.fromDate(nowLocal),
      });
    }

    await batch.commit();
  }
}
