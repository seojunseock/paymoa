// lib/screens/role_gate_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../common/app_words.dart';
import '../data/user_role_repository.dart';
import '../ui/app_shell.dart';
import 'role_selection_screen.dart';

class RoleGateScreen extends StatefulWidget {
  const RoleGateScreen({super.key});

  @override
  State<RoleGateScreen> createState() => _RoleGateScreenState();
}

class _RoleGateScreenState extends State<RoleGateScreen> {
  final _repo = UserRoleRepository();

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후 네비게이션(컨텍스트 안전)
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final user = FirebaseAuth.instance.currentUser;

    // 1) 로그인 안됨
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const _LoginRequiredScreen(),
        ),
        (_) => false,
      );
      return;
    }

    // 2) 역할 조회
    final role = await _repo.getRoleOnce();
    if (!mounted) return;

    // 2-1) 역할 미선택 → 선택 화면
    if (role == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (_) => false,
      );
      return;
    }

    // 3) 역할별 라우팅
    if (role == UserRole.worker) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
      return;
    }

    // owner
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const _OwnerHomePlaceholder()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _LoginRequiredScreen extends StatelessWidget {
  const _LoginRequiredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(AppWords.loginRequired),
      ),
    );
  }
}

class _OwnerHomePlaceholder extends StatelessWidget {
  const _OwnerHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppWords.ownerTitle)),
      body: const Center(
        child: Text(AppWords.ownerComingSoon),
      ),
    );
  }
}
