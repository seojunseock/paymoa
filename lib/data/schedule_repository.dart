// lib/data/schedule_repository.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ui_calendar_models.dart';
import '../models/store_schedule.dart';
import '../data/my_store_join_repository.dart'; // ✅ ActiveJoinPath

class ScheduleRepository {
  ScheduleRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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

  int _dateKey(int y, int m, int d) => (y * 10000 + m * 100 + d);

  // ─────────────────────────────
  // ✅ docPath 기반 "무조건 삭제/수정"
  // ─────────────────────────────
  Future<void> deleteScheduleByDocPath(String docPath) async {
    if (docPath.trim().isEmpty) throw StateError('docPath가 비어있어요.');
    await _db.doc(docPath).delete();
  }

  Future<void> updateScheduleByDocPath({
    required String docPath,
    required Map<String, dynamic> data,
  }) async {
    if (docPath.trim().isEmpty) throw StateError('docPath가 비어있어요.');
    await _db.doc(docPath).set(data, SetOptions(merge: true));
  }

  // ─────────────────────────────
  // ✅ PERSONAL schedules
  // ─────────────────────────────
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

  // ─────────────────────────────
  // ✅ JOIN schedules
  // - active join 목록 기준으로만 store schedules를 구독
  // ─────────────────────────────
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

  // ─────────────────────────────
  // ✅ JOIN + PERSONAL merge (V2)
  // ─────────────────────────────
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

  // ─────────────────────────────
  // ADD (personal / join)
  // ─────────────────────────────
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

    // JOIN 추가(사장님 원본에 추가)
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

    // PERSONAL
    await _mySchedulesRef(workerUid).add({
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─────────────────────────────
  // ✅ "스케줄 객체"로 업데이트/삭제 (docPath 우선)
  // ─────────────────────────────
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

    // PERSONAL fallback
    await _mySchedulesRef(workerUid)
        .doc(ui.id)
        .set(data, SetOptions(merge: true));
  }

  Future<void> deleteScheduleSmart({
    required String workerUid,
    required UICalendarSchedule ui,
  }) async {
    if (ui.id.trim().isEmpty) throw StateError('삭제할 scheduleId가 비어있어요.');

    if (ui.docPath != null && ui.docPath!.trim().isNotEmpty) {
      await deleteScheduleByDocPath(ui.docPath!);
      return;
    }

    // PERSONAL fallback
    await _mySchedulesRef(workerUid).doc(ui.id).delete();
  }

  // ─────────────────────────────
  // JOIN schedules → UI
  // ─────────────────────────────
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
      docPath: doc.reference.path, // ✅ 핵심
    );
  }

  // ─────────────────────────────
  // PERSONAL schedules → UI
  // ─────────────────────────────
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
      docPath: doc.reference.path, // ✅ 핵심
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
