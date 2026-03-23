// lib/screens/consent_screen.dart
import 'package:flutter/material.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';

class ConsentScreen extends StatefulWidget {
  final Future<void> Function() onAgreed;

  const ConsentScreen({super.key, required this.onAgreed});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _loading = false;

  bool get _allAgreed => _terms && _privacy;

  void _toggleAll(bool value) {
    setState(() {
      _terms = value;
      _privacy = value;
    });
  }

  Future<void> _submit() async {
    if (!_allAgreed || _loading) return;

    setState(() => _loading = true);
    try {
      await widget.onAgreed();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),

                      // ── 앱 아이콘
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        '페이모아',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Text(
                        '서비스 이용을 위해\n약관에 동의해 주세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          height: 1.55,
                        ),
                      ),

                      const Spacer(flex: 3),

                      // ── 동의 카드
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x1F7C3AED)),
                        ),
                        child: Column(
                          children: [
                            // 전체 동의
                            InkWell(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              onTap: () => _toggleAll(!_allAgreed),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    _Checkbox(
                                      value: _allAgreed,
                                      onChanged: _toggleAll,
                                      filled: true,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        '전체 동의',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1F2937),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const Divider(height: 1, indent: 16, endIndent: 16),

                            // 이용약관
                            _ConsentRow(
                              label: '(필수) 이용약관 동의',
                              checked: _terms,
                              onChanged: (v) => setState(() => _terms = v),
                              onViewTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                            ),

                            const Divider(height: 1, indent: 16, endIndent: 16),

                            // 개인정보처리방침
                            _ConsentRow(
                              label: '(필수) 개인정보처리방침 동의',
                              checked: _privacy,
                              onChanged: (v) => setState(() => _privacy = v),
                              onViewTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── 시작하기 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _allAgreed ? _submit : null,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                _allAgreed ? purple : const Color(0xFFD1D5DB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('시작하기'),
                        ),
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── 체크박스
class _Checkbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool filled;

  const _Checkbox({
    required this.value,
    required this.onChanged,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value ? purple : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value ? purple : const Color(0xFFD1D5DB),
            width: 1.8,
          ),
        ),
        child: value
            ? const Icon(Icons.check, color: Colors.white, size: 14)
            : null,
      ),
    );
  }
}

// ── 동의 항목 행
class _ConsentRow extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onViewTap;

  const _ConsentRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    required this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Checkbox(value: checked, onChanged: onChanged),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onViewTap,
              child: const Text(
                '보기',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
