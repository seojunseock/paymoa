// lib/ui/app_shell_owner.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/owner/owner_store_list_screen.dart';
import '../auth/auth_service.dart';

class OwnerAppShell extends StatefulWidget {
  const OwnerAppShell({super.key});

  @override
  State<OwnerAppShell> createState() => _OwnerAppShellState();
}

class _OwnerAppShellState extends State<OwnerAppShell> {
  int _index = 0;

  Future<bool> _confirm(BuildContext context, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
    // RoleGate(authStateChanges)가 LoginScreen으로 자동 이동
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ⚠️ 최근 로그인 필요 에러가 날 수 있음 (Firebase 정책)
    await user.delete();
    // 성공하면 authStateChanges로 자동 이동
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const OwnerStoreListScreen(),
      OwnerMyScreen(
        onLogout: () async {
          final ok = await _confirm(context, '로그아웃 하시겠어요?');
          if (!ok) return;

          try {
            await _logout();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('로그아웃 실패: $e')),
            );
          }
        },
        onDeleteAccount: () async {
          final ok = await _confirm(
            context,
            '회원탈퇴 하시겠어요?\n(계정만 삭제됩니다. 데이터는 별도 정책이 필요해요)\n\n* 최근 로그인 필요 에러가 뜰 수 있어요.',
          );
          if (!ok) return;

          try {
            await _deleteAccount();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('탈퇴 실패: $e')),
            );
          }
        },
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront), label: '매장'),
          NavigationDestination(icon: Icon(Icons.person), label: '내정보'),
        ],
      ),
    );
  }
}

class OwnerMyScreen extends StatelessWidget {
  const OwnerMyScreen({
    super.key,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보(사장님)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.description),
                  title: Text('서비스 이용약관'),
                  trailing: Icon(Icons.chevron_right),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.privacy_tip),
                  title: Text('개인정보 처리방침'),
                  trailing: Icon(Icons.chevron_right),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.receipt_long),
                  title: Text('오픈소스 라이선스'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.redAccent,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.white),
                  title:
                      const Text('로그아웃', style: TextStyle(color: Colors.white)),
                  trailing:
                      const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: onLogout,
                ),
                const Divider(height: 1, color: Colors.white24),
                ListTile(
                  leading:
                      const Icon(Icons.delete_forever, color: Colors.white),
                  title:
                      const Text('회원탈퇴', style: TextStyle(color: Colors.white)),
                  trailing:
                      const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: onDeleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
