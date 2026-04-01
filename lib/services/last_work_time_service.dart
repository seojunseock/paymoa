// lib/services/last_work_time_service.dart
//
// 매장별 마지막 근무시간을 로컬에 저장/불러오기.
// 알바 폼과 워크 에디터에서 공유.

import 'package:shared_preferences/shared_preferences.dart';

typedef LastWorkTime = ({
  int startH,
  int startM,
  int endH,
  int endM,
  int breakMin,
});

class LastWorkTimeService {
  static const _prefix = 'lwt_';

  static Future<void> save({
    required String albaId,
    required int startH,
    required int startM,
    required int endH,
    required int endM,
    required int breakMin,
  }) async {
    if (albaId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_prefix}sh_$albaId', startH);
    await prefs.setInt('${_prefix}sm_$albaId', startM);
    await prefs.setInt('${_prefix}eh_$albaId', endH);
    await prefs.setInt('${_prefix}em_$albaId', endM);
    await prefs.setInt('${_prefix}bm_$albaId', breakMin);
  }

  static Future<LastWorkTime?> load(String albaId) async {
    if (albaId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final startH = prefs.getInt('${_prefix}sh_$albaId');
    if (startH == null) return null;
    return (
      startH: startH,
      startM: prefs.getInt('${_prefix}sm_$albaId') ?? 0,
      endH: prefs.getInt('${_prefix}eh_$albaId') ?? 18,
      endM: prefs.getInt('${_prefix}em_$albaId') ?? 0,
      breakMin: prefs.getInt('${_prefix}bm_$albaId') ?? 0,
    );
  }
}
