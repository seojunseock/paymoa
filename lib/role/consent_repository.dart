import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConsentRepository {
  static const _prefix = 'consent_agreed__';
  static const _version = '1.0'; // 약관 버전 — 개정 시 올리면 재동의 요구 가능
  static final StreamController<String> _changed =
      StreamController<String>.broadcast();

  final FirebaseFirestore _db;

  ConsentRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  String _keyOf(String uid) => '$_prefix$uid';

  Stream<bool> watchConsent(String uid) async* {
    final id = uid.trim();
    if (id.isEmpty) {
      yield false;
      return;
    }
    yield await hasAgreed(id);
    await for (final changedUid in _changed.stream) {
      if (changedUid != id) continue;
      yield await hasAgreed(id);
    }
  }

  Future<bool> hasAgreed(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOf(id)) ?? false;
  }

  /// 동의 처리:
  /// 1) 기기 로컬(SharedPreferences) — 빠른 읽기용
  /// 2) Firestore users/{uid}/consent — 서버 증거 기록
  Future<void> setAgreed(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;

    // 로컬 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOf(id), true);

    // Firestore 기록 (증거용 — 실패해도 로컬은 저장됨)
    try {
      await _db.collection('users').doc(id).set({
        'consent': {
          'agreed': true,
          'agreedAt': FieldValue.serverTimestamp(),
          'version': _version,
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // 오프라인 등 실패 시 무시 — 로컬 동의 기준으로 진행
    }

    _changed.add(id);
  }

  /// 탈퇴 시 동의 정보 정리:
  /// 1) 로컬 SharedPreferences 삭제
  /// 2) Firestore consent 필드 제거 시도
  Future<void> clearConsent(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;

    // 로컬 삭제
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOf(id));

    // Firestore 삭제 시도
    try {
      await _db.collection('users').doc(id).set({
        'consent': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {
      // 계정 삭제 흐름 중이므로 실패해도 로컬 삭제만 되면 충분
    }

    _changed.add(id);
  }
}
