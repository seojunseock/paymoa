import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store.dart';
import '../models/store_join_ref.dart';

class StoreRepository {
  StoreRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _storesRef(String uid) =>
      _db.collection('users').doc(uid).collection('stores');

  /// ✅ 전역 코드 맵: storeJoinCodes/{CODE}
  CollectionReference<Map<String, dynamic>> get _joinCodesRef =>
      _db.collection('storeJoinCodes');

  // ✅ 안전한 timestamp 파서
  DateTime _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ✅ 정렬키: updatedAt > createdAt > epoch
  DateTime _recentKey(Map<String, dynamic> m) {
    final u = _tsToDate(m['updatedAt']);
    if (u.millisecondsSinceEpoch != 0) return u;

    final c = _tsToDate(m['createdAt']);
    if (c.millisecondsSinceEpoch != 0) return c;

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ 장기 안정화:
  /// - orderBy(createdAt) 제거 (레거시 필드 누락/인덱스/런타임 오류 방지)
  /// - 로컬 정렬로 대체
  Stream<List<Store>> watchStores(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return const Stream<List<Store>>.empty();

    return _storesRef(id).snapshots().map((qs) {
      final docs = qs.docs.toList(growable: false);

      // ✅ 로컬 정렬: 최근 수정/생성 순
      final sorted = [...docs];
      sorted.sort((a, b) {
        final ak = _recentKey(a.data());
        final bk = _recentKey(b.data());
        final t = bk.compareTo(ak);
        if (t != 0) return t;

        // tie-breaker: 이름
        final an = ((a.data()['name'] ?? '') as String).trim();
        final bn = ((b.data()['name'] ?? '') as String).trim();
        return an.compareTo(bn);
      });

      return sorted.map(Store.fromDoc).toList();
    });
  }

  /// ✅ CREATE: Store를 리턴 (storeCode 포함)
  /// - store 문서 + storeJoinCodes 문서를 "배치"로 원자 저장
  /// - joinCodes 문서에는 알바가 읽어야 할 기본값/정책 스냅샷까지 저장
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

    // 1) 중복 없는 storeCode 생성
    final code = await _generateUniqueStoreCode();
    final trimmedName = name.trim();

    // 2) store 문서 데이터(사장 전용 원본)
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

    // 3) ✅ joinCodes 문서 데이터(알바가 읽는 스냅샷)
    final joinData = <String, dynamic>{
      'ownerUid': id,
      'storeId': storeRef.id,

      // 알바 폼에 바로 채우기 위해 같이 저장
      'storeName': trimmedName,
      'colorHex': colorHex,
      'defaultHourlyWage': defaultHourlyWage,
      'payDay': payDay,
      'storeCode': code,
      if (policy != null) 'policy': policy,

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 4) 배치로 원자 저장
    final batch = _db.batch();
    batch.set(storeRef, storeData);
    batch.set(_joinCodesRef.doc(code), joinData);
    await batch.commit();

    // 5) UI에서 즉시 쓰기 위해 Store를 만들어 리턴
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

  /// ✅ UPDATE
  /// - store 문서 업데이트 + joinCodes 문서도 같이 갱신(알바에게 최신값 전달)
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

    // storeCode 확인(사장만 읽기 가능)
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

    // ✅ joinCodes 갱신
    final code = storeCode.trim().toUpperCase();
    if (code.isNotEmpty) {
      final joinUpdates = <String, dynamic>{
        if (name != null) 'storeName': name.trim(),
        if (colorHex != null) 'colorHex': colorHex,
        if (defaultHourlyWage != null) 'defaultHourlyWage': defaultHourlyWage,
        if (payDay != null) 'payDay': payDay,
        if (policy != null) 'policy': policy,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(_joinCodesRef.doc(code), joinUpdates, SetOptions(merge: true));
    }

    await batch.commit();
  }

  /// ✅ DELETE (storeCode를 알면 join 맵도 같이 삭제)
  Future<void> deleteStore({
    required String uid,
    required String storeId,
    String? storeCode,
  }) async {
    final id = uid.trim();
    final sid = storeId.trim();
    if (id.isEmpty) throw StateError('uid empty');
    if (sid.isEmpty) throw StateError('storeId empty');

    final batch = _db.batch();
    batch.delete(_storesRef(id).doc(sid));

    final code = storeCode?.trim().toUpperCase();
    if (code != null && code.isNotEmpty) {
      batch.delete(_joinCodesRef.doc(code));
    }
    await batch.commit();
  }

  /// ✅ 코드 → JoinRef(ownerUid, storeId)
  Future<StoreJoinRef?> resolveJoinRefByCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;

    final doc = await _joinCodesRef.doc(c).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    final ownerUid = (data['ownerUid'] ?? '') as String;
    final storeId = (data['storeId'] ?? '') as String;
    if (ownerUid.isEmpty || storeId.isEmpty) return null;

    return StoreJoinRef(ownerUid: ownerUid, storeId: storeId);
  }

  /// ✅ 알바용: joinCodes 문서 메타 + policy까지 그대로 반환
  Future<Map<String, dynamic>?> fetchJoinCodeMeta(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;

    final doc = await _joinCodesRef.doc(c).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;

    final ownerUid = (data['ownerUid'] ?? '') as String;
    final storeId = (data['storeId'] ?? '') as String;
    if (ownerUid.isEmpty || storeId.isEmpty) return null;

    return data;
  }

  /// ✅ JoinRef로 실제 Store 읽기(사장 전용이지만 유지)
  Future<Store?> fetchStoreByJoinRef(StoreJoinRef ref) async {
    final doc = await _storesRef(ref.ownerUid).doc(ref.storeId).get();
    if (!doc.exists) return null;
    return Store.fromDoc(doc);
  }

  /// --- 내부: 중복 없는 코드 생성 ---
  Future<String> _generateUniqueStoreCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();

    String gen() {
      final sb = StringBuffer();
      for (int i = 0; i < 8; i++) {
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
}
