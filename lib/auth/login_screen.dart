// lib/auth/login_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _loadingProvider;

  Future<void> _login(String provider) async {
    setState(() {
      _loading = true;
      _loadingProvider = provider;
    });
    try {
      switch (provider) {
        case 'kakao':
          await AuthService.instance.signInWithKakao();
          break;
        case 'google':
          await AuthService.instance.signInWithGoogle();
          break;
        case 'apple':
          await AuthService.instance.signInWithApple();
          break;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('로그인 성공!'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('로그인 실패: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── 로고 (앱 아이콘 이미지)
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withAlpha(20),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withAlpha(12),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/images/splash_logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text('페이모아',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1F2937),
                      letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text('알바 급여 관리, 이제 간편하게',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280))),

              const Spacer(flex: 3),

              // ── 카카오 ───────────────────────────────
              _LoginButton(
                provider: 'kakao',
                loading: _loading && _loadingProvider == 'kakao',
                backgroundColor: const Color(0xFFFEE500),
                textColor: const Color(0xFF191919),
                iconWidget: const _KakaoIcon(),
                label: '카카오로 시작하기',
                onTap: () => _login('kakao'),
              ),
              const SizedBox(height: 12),

              // ── 구글 ─────────────────────────────────
              _LoginButton(
                provider: 'google',
                loading: _loading && _loadingProvider == 'google',
                backgroundColor: Colors.white,
                textColor: const Color(0xFF1F2937),
                iconWidget: const _GoogleIcon(),
                label: 'Google로 시작하기',
                border: true,
                onTap: () => _login('google'),
              ),

              // ── 애플 (iOS에서만 표시) ──────────────────
              if (isIOS) ...[
                const SizedBox(height: 12),
                _LoginButton(
                  provider: 'apple',
                  loading: _loading && _loadingProvider == 'apple',
                  backgroundColor: const Color(0xFF000000),
                  textColor: Colors.white,
                  iconWidget:
                      const Icon(Icons.apple, color: Colors.white, size: 22),
                  label: 'Apple로 시작하기',
                  onTap: () => _login('apple'),
                ),
              ],

              const Spacer(flex: 2),

              const Text(
                '로그인하면 이용약관 및 개인정보처리방침에 동의하게 됩니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF9CA3AF), height: 1.4),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공통 버튼
// ─────────────────────────────────────────────
class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.provider,
    required this.loading,
    required this.backgroundColor,
    required this.textColor,
    required this.iconWidget,
    required this.label,
    required this.onTap,
    this.border = false,
  });

  final String provider;
  final bool loading;
  final Color backgroundColor;
  final Color textColor;
  final Widget iconWidget;
  final String label;
  final VoidCallback onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: border ? 0 : 1,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: border
                ? const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)
                : BorderSide.none,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(textColor)),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget,
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor)),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 아이콘들
// ─────────────────────────────────────────────

class _KakaoIcon extends StatelessWidget {
  const _KakaoIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration:
          const BoxDecoration(color: Color(0xFF191919), shape: BoxShape.circle),
      child: const Center(
        child: Text('K',
            style: TextStyle(
                color: Color(0xFFFEE500),
                fontSize: 13,
                fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Center(
        child: Text('G',
            style: TextStyle(
                color: Color(0xFF4285F4),
                fontSize: 13,
                fontWeight: FontWeight.w900)),
      ),
    );
  }
}
