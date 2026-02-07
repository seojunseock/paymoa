import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/login_screen.dart';
import 'role_selection_screen.dart';
import 'role_repository.dart';

import '../ui/app_shell.dart'; // 알바생
import '../ui/app_shell_owner.dart'; // 사장님

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;

        // 1) 로그인 안 됨 → 로그인 화면
        if (user == null) {
          return const LoginScreen();
        }

        final uid = user.uid.trim();
        if (uid.isEmpty) {
          // ✅ 극단 케이스 방어
          return const LoginScreen();
        }

        final repo = RoleRepository();

        // 2) 로그인 됨 → 역할 스트림
        return StreamBuilder<UserRole?>(
          stream: repo.watchRole(uid),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final role = roleSnap.data;

            // 3) 저장된 역할 있음 → 바로 진입 (✅ 여기만이 진입 책임)
            if (role != null) {
              return role == UserRole.owner
                  ? const OwnerAppShell()
                  : const AppShell();
            }

            // 4) 역할 없음 → 선택 화면
            return RoleSelectionScreen(
              onPick: (UserRole picked) async {
                // ✅ 네비게이션 금지(중복 전환 방지)
                // setRole만 하면 watchRole이 변하고 RoleGate가 자동 진입함.
                await repo.setRole(uid, picked);
              },
            );
          },
        );
      },
    );
  }
}
