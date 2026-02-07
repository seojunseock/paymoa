import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { owner, alba }

class RoleRepository {
  static const _prefix = 'user_role__'; // ✅ uid별 key 분리
  String _keyOf(String uid) => '$_prefix$uid';

  // ✅ 변경 알림 브로드캐스트
  static final StreamController<String> _changed =
      StreamController<String>.broadcast();

  /// ✅ 장기 안정화:
  /// - StreamBuilder 단일 구독에 최적(불필요한 StreamController 생성/관리 제거)
  /// - 최초 1회 emit + 이후 uid 변경 이벤트 때마다 re-emit
  Stream<UserRole?> watchRole(String uid) async* {
    final id = uid.trim();
    if (id.isEmpty) {
      yield null;
      return;
    }

    // 최초 emit
    yield await getRole(id);

    // 변경 이벤트 때마다 emit
    await for (final changedUid in _changed.stream) {
      if (changedUid != id) continue;
      yield await getRole(id);
    }
  }

  Future<UserRole?> getRole(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyOf(id));
    if (v == null) return null;

    for (final r in UserRole.values) {
      if (r.name == v) return r;
    }
    return null;
  }

  Future<void> setRole(String uid, UserRole role) async {
    final id = uid.trim();
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOf(id), role.name);
    _changed.add(id);
  }

  Future<void> clearRole(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOf(id));
    _changed.add(id);
  }
}
