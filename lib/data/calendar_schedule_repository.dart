// lib/data/calendar_schedule_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ui_calendar_models.dart';

class CalendarScheduleRepository {
  CalendarScheduleRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ✅ 달력은 앞으로 여기만 봄
  // users/{uid}/calendarSchedules/{scheduleId}
  CollectionReference<Map<String, dynamic>> _calRef(String uid) =>
      _db.collection('users').doc(uid).collection('calendarSchedules');

  // ✅ JOIN 원본(사장님 매장 아래)
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

  // ─────────────────────────────
  // ✅ 달력 스케줄 스트림 (이것만 쓰면 됨)
  // - 숨김(isHidden=true)은 제외
  // ─────────────────────────────
  Stream<List<UICalendarSchedule>> watchMyCalendarSchedulesUi({
    required String workerUid,
  }) {
    if (workerUid.isEmpty) {
      return const Stream<List<UICalendarSchedule>>.empty();
    }

    return _calRef(workerUid)
        .where('isHidden', isNotEqualTo: true)
        .orderBy('isHidden') // Firestore 규칙: where(isNotEqualTo) + orderBy 필요
        .orderBy('dateKey', descending: false)
        .orderBy('startMin', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map(_uiFromCalendarDoc).toList(growable: false));
  }

  // ─────────────────────────────
  // ✅ ADD - PERSONAL (내 달력에만 저장)
  // ─────────────────────────────
  Future<void> addPersonalFromUi({
    required String workerUid,
    required UICalendarSchedule ui,
  }) async {
    final y = ui.year;
    final m = ui.month;
    final d = ui.day;
    final dateKey = y * 10000 + m * 100 + d;
    final startMin = ui.startHour * 60 + ui.startMinute;

    final doc = _calRef(workerUid).doc(); // auto id
    await doc.set({
      'sourceType': 'personal', // ✅ rules에서 personal만 쓰기 허용
      'ownerUid': null,
      'storeId': null,

      'isHidden': false,

      'workerUid': workerUid,
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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────
  // ✅ ADD - JOIN
  // - 원본: users/{ownerUid}/stores/{storeId}/schedules/{id}
  // - 미러: users/{workerUid}/calendarSchedules/{id}
  // - ✅ 같은 scheduleId로 저장 (수정/삭제 안정화)
  // ─────────────────────────────
  Future<void> addJoinFromUi({
    required String workerUid,
    required String ownerUid,
    required String storeId,
    required UICalendarSchedule ui,
  }) async {
    final y = ui.year;
    final m = ui.month;
    final d = ui.day;
    final dateKey = y * 10000 + m * 100 + d;
    final startMin = ui.startHour * 60 + ui.startMinute;

    final db = _db;
    final batch = db.batch();

    final storeDoc =
        _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId).doc();
    final calDoc = _calRef(workerUid).doc(storeDoc.id);

    final payload = <String, dynamic>{
      'workerUid': workerUid,
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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 1) 원본(사장님) 저장
    batch.set(storeDoc, payload);

    // 2) 내 달력 미러 (JOIN 표시용 메타 포함)
    batch.set(calDoc, {
      'sourceType': 'join',
      'ownerUid': ownerUid,
      'storeId': storeId,
      'isHidden': false,
      ...payload,
    });

    await batch.commit();
  }

  // ─────────────────────────────
  // ✅ UPDATE
  // - personal: 내 달력만 업데이트
  // - join: 내 달력 + (사장님 원본도) 업데이트
  // ─────────────────────────────
  Future<void> updateFromUi({
    required String workerUid,
    required UICalendarSchedule ui,
  }) async {
    final calDoc = _calRef(workerUid).doc(ui.id);
    final snap = await calDoc.get();
    if (!snap.exists) {
      throw StateError('수정할 스케줄을 찾지 못했어요. (calendarSchedules)');
    }

    final data = snap.data() ?? {};
    final sourceType = (data['sourceType'] as String?) ?? 'personal';
    final ownerUid = (data['ownerUid'] as String?) ?? '';
    final storeId = (data['storeId'] as String?) ?? '';

    final y = ui.year;
    final m = ui.month;
    final d = ui.day;
    final dateKey = y * 10000 + m * 100 + d;
    final startMin = ui.startHour * 60 + ui.startMinute;

    final patch = <String, dynamic>{
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

    final batch = _db.batch();
    batch.update(calDoc, patch);

    if (sourceType == 'join') {
      if (ownerUid.isEmpty || storeId.isEmpty) {
        throw StateError('JOIN 스케줄인데 ownerUid/storeId가 없어요.');
      }
      final storeDoc =
          _storeSchedulesRef(ownerUid: ownerUid, storeId: storeId).doc(ui.id);
      batch.update(storeDoc, patch);
    }

    await batch.commit();
  }

  // ─────────────────────────────
  // ✅ DELETE (너가 원하는 정책 반영)
  //
  // - personal: 완전 삭제 (내 달력 문서 삭제)
  // - join: "알바생 화면에서만 삭제" → 내 달력에서 숨김 처리
  //         (사장님 원본 schedules는 절대 삭제하지 않음)
  // ─────────────────────────────
  Future<void> deleteById({
    required String workerUid,
    required String scheduleId,
  }) async {
    final sid = scheduleId.trim();
    if (workerUid.trim().isEmpty || sid.isEmpty) return;

    final calDoc = _calRef(workerUid).doc(sid);
    final snap = await calDoc.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final sourceType = (data['sourceType'] as String?) ?? 'personal';

    if (sourceType == 'personal') {
      await calDoc.delete();
      return;
    }

    // join: 숨김(내 화면에서만 제거)
    await calDoc.update({
      'isHidden': true,
      'hiddenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ✅ 사장님 원본은 남겨둔다 (세무/정산 목적)
  }

  // ─────────────────────────────
  // calendarSchedules → UI
  // ─────────────────────────────
  UICalendarSchedule _uiFromCalendarDoc(
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
}
