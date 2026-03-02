// lib/controllers/app_shell_controller.dart
import 'package:flutter/foundation.dart';

import '../data/firebase_service.dart';

/// AppShell에서 섞여있던 "상태/데이터 로딩/로컬 캐시" 책임을 UI 밖으로 빼기 위한 컨트롤러.
/// 1차 안정화에서는 '탭 상태 + 레포 주입 + dispose'부터 시작하고,
/// 2차부터 AppShell의 로직을 단계적으로 이쪽으로 이동합니다.
class AppShellController extends ChangeNotifier {
  AppShellController({
    FirebaseService? firebaseService,
  }) : _firebaseService = firebaseService ?? FirebaseService();

  final FirebaseService _firebaseService;

  int _tabIndex = 0;

  int get tabIndex => _tabIndex;

  FirebaseService get firebaseService => _firebaseService;

  void setTab(int index) {
    if (index == _tabIndex) return;
    _tabIndex = index;
    notifyListeners();
  }

  @override
  void dispose() {
    // Repository들이 StreamController 등을 내부에서 관리하지 않는 한 별도 dispose는 필요없음.
    // (추후 repo가 dispose를 제공하면 여기서 호출)
    super.dispose();
  }
}
