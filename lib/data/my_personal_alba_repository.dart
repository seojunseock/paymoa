// lib/data/my_personal_alba_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ui_calendar_models.dart';

class MyPersonalAlbaRepository {
  MyPersonalAlbaRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // users/{uid}/myAlbas/{albaId}
  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('myAlbas');

  Stream<List<UICalendarAlba>> watchMyPersonalAlbas(String uid) {
    return _ref(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map((doc) {
              final d = doc.data();
              return UICalendarAlba(
                id: doc.id,
                storeId: '', // 개인 알바는 storeId 없음
                name: (d['name'] as String?) ?? '개인 알바',
                hourlyWage: (d['hourlyWage'] as num?)?.toInt() ?? 0,
                colorHex: (d['colorHex'] as String?) ?? '#3B82F6',
                payDay: (d['payDay'] as num?)?.toInt() ?? 25,
              );
            }).toList(growable: false));
  }

  Future<String> addPersonalAlba({
    required String uid,
    required String name,
    required int hourlyWage,
    required String colorHex,
    required int payDay,
  }) async {
    final doc = await _ref(uid).add({
      'name': name,
      'hourlyWage': hourlyWage,
      'colorHex': colorHex,
      'payDay': payDay,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> deletePersonalAlba({
    required String uid,
    required String albaId,
  }) async {
    await _ref(uid).doc(albaId).delete();
  }
}
