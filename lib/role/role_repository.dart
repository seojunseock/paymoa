import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { owner, alba }

class RoleRepository {
  static const _prefix = 'user_role__'; // ✅ uid별 key 분리
  String _keyOf(String uid) => '$_prefix$uid';

  // ✅ uid별 역할 변경 알림 브로드캐스트
  static final StreamController<String> _changed =
      StreamController<String>.broadcast();

  /// ✅ uid 기준 역할 스트림
  /// - 최초 1회 현재 저장값 emit
  /// - 이후 같은 uid에 대한 set/clear 발생 시 다시 emit
  Stream<UserRole?> watchRole(String uid) async* {
    final id = uid.trim();
    if (id.isEmpty) {
      yield null;
      return;
    }

    // 최초 emit
    yield await getRole(id);

    // 변경 이벤트 반영
    await for (final changedUid in _changed.stream) {
      if (changedUid != id) continue;
      yield await getRole(id);
    }
  }

  Future<UserRole?> getRole(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOf(id));
    if (raw == null) return null;

    for (final role in UserRole.values) {
      if (role.name == raw) return role;
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
