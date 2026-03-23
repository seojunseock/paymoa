import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/login_screen.dart';
import 'role_selection_screen.dart';
import 'role_repository.dart';
import 'consent_repository.dart';
import '../screens/consent_screen.dart';

import '../ui/app_shell.dart'; // 알바생
import '../ui/app_shell_owner.dart'; // 사장님

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  Widget _loading() {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final consentRepo = ConsentRepository();
    final roleRepo = RoleRepository();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return _loading();
        }

        final user = authSnap.data;

        // 1) 로그인 안 됨 → 로그인 화면
        if (user == null) {
          return const LoginScreen();
        }

        final uid = user.uid.trim();
        if (uid.isEmpty) {
          return const LoginScreen();
        }

        // 2) 약관 동의 확인
        return StreamBuilder<bool>(
          stream: consentRepo.watchConsent(uid),
          builder: (context, consentSnap) {
            if (consentSnap.connectionState == ConnectionState.waiting) {
              return _loading();
            }

            final agreed = consentSnap.data ?? false;

            // 3) 미동의 → 동의 화면
            if (!agreed) {
              return ConsentScreen(
                onAgreed: () async {
                  await consentRepo.setAgreed(uid);
                },
              );
            }

            // 4) 동의 완료 → 역할 확인
            return StreamBuilder<UserRole?>(
              stream: roleRepo.watchRole(uid),
              builder: (context, roleSnap) {
                if (roleSnap.connectionState == ConnectionState.waiting) {
                  return _loading();
                }

                final role = roleSnap.data;

                // 5) 저장된 역할이 있으면 바로 진입
                if (role != null) {
                  return role == UserRole.owner
                      ? const OwnerAppShell()
                      : const AppShell();
                }

                // 6) 역할이 없으면 처음 1회만 선택
                return RoleSelectionScreen(
                  onPick: (UserRole picked) async {
                    // ✅ 여기서 네비게이션 직접 하지 않음
                    // 역할 저장만 하면 watchRole이 다시 emit되고
                    // RoleGate가 자동으로 해당 쉘로 분기함
                    await roleRepo.setRole(uid, picked);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
