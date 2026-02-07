// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';

import '../common/app_words.dart';
import '../data/user_role_repository.dart';
import 'role_gate_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _saving = false;
  final _repo = UserRoleRepository();

  Future<void> _select(UserRole role) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await _repo.setRole(role);
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleGateScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.saveFailed}\n$e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppWords.startTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text(
              AppWords.rolePickTitle,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              AppWords.rolePickHint,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _select(UserRole.owner),
                icon: const Icon(Icons.storefront),
                label: Text(_saving ? AppWords.saving : AppWords.owner),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _select(UserRole.worker),
                icon: const Icon(Icons.badge),
                label: Text(_saving ? AppWords.saving : AppWords.worker),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
