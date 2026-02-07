import 'package:flutter/material.dart';
import 'role_repository.dart';

class RoleSelectionScreen extends StatefulWidget {
  final Future<void> Function(UserRole role) onPick;
  const RoleSelectionScreen({super.key, required this.onPick});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _busy = false;

  Future<void> _handlePick(UserRole role) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      // ✅ 여기서는 저장만 수행 (RoleGate가 자동으로 Shell로 전환)
      await widget.onPick(role);

      // RoleGate가 rebuild되면서 이 화면이 dispose될 수 있으므로,
      // 여기서 추가 네비게이션/상태 변경은 하지 않음.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('역할 선택 중 오류가 발생했어요: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('시작하기'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '어떤 역할로 시작할까요?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '한 번만 선택하면 다음 로그인부터 자동으로 바로 들어가요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                enabled: !_busy,
                title: '사장님으로 시작',
                subtitle: '매장 등록 · 알바 급여/세무 문서 관리',
                icon: Icons.store_outlined,
                accent: theme.colorScheme.primary,
                onTap: () => _handlePick(UserRole.owner),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                enabled: !_busy,
                title: '알바생으로 시작',
                subtitle: '근무 기록 · 나의 급여/정산 확인',
                icon: Icons.badge_outlined,
                accent: theme.colorScheme.tertiary,
                onTap: () => _handlePick(UserRole.alba),
              ),
              const Spacer(),
              if (_busy)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 10),
                      Text(
                        '이동 중…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final bool enabled;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withOpacity(0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
