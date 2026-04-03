// lib/auth/login_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_service.dart';
import '../common/paymoa_design.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _loadingProvider;

  Future<void> _login(String provider) async {
    if (_loading) return;

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
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '로그인에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingProvider = null;
      });
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const Spacer(),
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF7C3AED).withOpacity(0.27),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFF3F0FF),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.apps_rounded,
                                    size: 40,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          '페이모아',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1F2937),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '알바 급여 관리, 이제 간편하게',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            _FeatureChip(
                              icon: Icons.calculate_rounded,
                              label: '급여 자동계산',
                            ),
                            _FeatureChip(
                              icon: Icons.calendar_month_rounded,
                              label: '근무 일정 관리',
                            ),
                            _FeatureChip(
                              icon: Icons.table_chart_rounded,
                              label: '엑셀 내보내기',
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (isIOS) ...[
                          _AppleLoginButton(
                            loading: _loading && _loadingProvider == 'apple',
                            onTap: () => _login('apple'),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _KakaoLoginButton(
                          loading: _loading && _loadingProvider == 'kakao',
                          onTap: () => _login('kakao'),
                        ),
                        const SizedBox(height: 14),
                        _GoogleLoginButton(
                          loading: _loading && _loadingProvider == 'google',
                          onTap: () => _login('google'),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            GestureDetector(
                              onTap: () => _launchExternalUrl(
                                'https://funky-mandevilla-5dc.notion.site/Terms-of-Service-9a7d10d5a0394f2a9cee324fe89893a7',
                              ),
                              child: const Text(
                                '이용약관',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9CA3AF),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _launchExternalUrl(
                                'https://funky-mandevilla-5dc.notion.site/Privacy-Policy-599f1871c09d40d782e5c1936444f6ac',
                              ),
                              child: const Text(
                                '개인정보처리방침',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9CA3AF),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

// 카카오 버튼
class _KakaoLoginButton extends StatelessWidget {
  const _KakaoLoginButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE500),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(Color(0xFF191919)),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: const Color(0xFFFEE500),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Image.asset(
                'assets/images/login/kakao_login_large_wide.png',
                fit: BoxFit.contain,
                height: 56,
                width: double.infinity,
                filterQuality: FilterQuality.high,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text(
                    '카카오로 시작하기',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xD9000000),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 구글 버튼
class _GoogleLoginButton extends StatelessWidget {
  const _GoogleLoginButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDADCE0), width: 1),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(Color(0xFF4285F4)),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDADCE0), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/google_icon.png',
              width: 18,
              height: 18,
              errorBuilder: (_, __, ___) =>
                  const SizedBox(width: 18, height: 18),
            ),
            const SizedBox(width: 24),
            const Expanded(
              child: Text(
                'Google 계정으로 로그인',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F1F1F),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// 애플 버튼
class _AppleLoginButton extends StatelessWidget {
  const _AppleLoginButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: loading ? 0.7 : 1,
      child: SizedBox(
        height: 56,
        child: SignInWithAppleButton(
          onPressed: () {
            if (loading) return;
            onTap();
          },
          style: SignInWithAppleButtonStyle.black,
          text: 'Apple로 로그인',
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}

// 기능 소개 칩
class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF7C3AED), size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

//flutter clean
//flutter pub get
//flutter build apk --release
//& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
//& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r .\build\app\outputs\flutter-apk\app-release.apk
