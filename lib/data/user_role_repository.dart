import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum UserRole { owner, worker }

class UserRoleRepository {
  UserRoleRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('profile');

  /// role 저장 (owner / worker)
  Future<void> setRole(UserRole role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');

    await _profileRef(user.uid).set({
      'role': role.name, // "owner" or "worker"
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// role 1회 읽기
  Future<UserRole?> getRoleOnce() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final snap = await _profileRef(user.uid).get();
    final data = snap.data();
    if (data == null) return null;

    final roleStr = (data['role'] as String?)?.trim();
    if (roleStr == null || roleStr.isEmpty) return null;

    if (roleStr == 'owner') return UserRole.owner;
    if (roleStr == 'worker') return UserRole.worker;
    return null;
  }

  /// role 실시간
  Stream<UserRole?> watchRole() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);

    return _profileRef(user.uid).snapshots().map((snap) {
      final data = snap.data();
      final roleStr = (data?['role'] as String?)?.trim();
      if (roleStr == 'owner') return UserRole.owner;
      if (roleStr == 'worker') return UserRole.worker;
      return null;
    });
  }
}
