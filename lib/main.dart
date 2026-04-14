// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'ads/ad_service.dart';

import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'firebase_options.dart';
import 'role/role_gate.dart';
import 'screens/terms_screen.dart';
import 'screens/privacy_policy_screen.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

bool _fatalHandling = false; // ✅ 에러 처리 중복/무한루프 방지
bool _fatalDialogShowing = false; // ✅ 다이얼로그 중복 방지

// Firebase + 날짜 초기화를 한 번만 실행하는 Future
final Future<void> _appInitFuture = Future(() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting('ko_KR', null);
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _showFatalSafely(
      title: 'FlutterError',
      message: details.exceptionAsString(),
      st: details.stack,
    );
  };

  // runApp을 가장 먼저 호출 — SDK 초기화 실패와 무관하게 화면이 뜸
  runApp(const _SafeBootApp());

  // 카카오 SDK 초기화
  try {
    KakaoSdk.init(nativeAppKey: '53dfe716642af3a731da9865a25e5db6');
  } catch (e, st) {
    debugPrint('[main] KakaoSdk init error: $e\n$st');
  }

  // AdMob·RevenueCat 백그라운드 초기화
  unawaited(MobileAds.instance.initialize().then((_) {
    AdService.instance.preloadRewardedAd();
    AdService.instance.preloadInterstitialAd();
  }));

  unawaited(Purchases.configure(
    PurchasesConfiguration(
      Platform.isIOS
        ? 'appl_ChXJNrQtALfELGAcbtbDwWKLTww'
        : 'goog_rktGmHUQOMvyZPNdOLnEHHzcgrx',
    ),
  ));
}

class _SafeBootApp extends StatelessWidget {
  const _SafeBootApp();

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C3AED), // ✅ Paymoa violet-700
      brightness: Brightness.light,
    );

    // ✅ Paymoa 보라 톤
    final cs = base.copyWith(
      primary: const Color(0xFF7C3AED), // violet-700
      primaryContainer: const Color(0xFFF3EEFF), // 연한 보라
      onPrimaryContainer: const Color(0xFF3B0764),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8F7FF), // Paymoa background
      surfaceContainer: const Color(0xFFF4F0FF), // 연보라
      outline: const Color(0x1F0F172A),
    );

    final radius = BorderRadius.circular(16);

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Paymoa',
      debugShowCheckedModeBanner: false,
      color: Colors.white, // 앱 전환 시 배경색 (검은 화면 방지)
      // ✅ DatePicker 한국어 및 Material Localization 설정
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ko', 'KR'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        scaffoldBackgroundColor: cs.surfaceContainerLow,
        appBarTheme: AppBarTheme(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
          iconTheme: IconThemeData(color: cs.onSurface.withOpacity(0.85)),
        ),
        cardTheme: CardTheme(
          color: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: cs.outline.withOpacity(0.25)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            shape: RoundedRectangleBorder(borderRadius: radius),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: radius),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface.withOpacity(0.85),
            side: BorderSide(color: cs.outline.withOpacity(0.35)),
            shape: RoundedRectangleBorder(borderRadius: radius),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: cs.primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cs.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: cs.outline.withOpacity(0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: cs.outline.withOpacity(0.28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide:
                BorderSide(color: cs.primary.withOpacity(0.55), width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: cs.surfaceContainerLow,
          selectedColor: cs.primaryContainer,
          side: BorderSide(color: cs.outline.withOpacity(0.25)),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface.withOpacity(0.85),
          ),
          secondaryLabelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onPrimaryContainer,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF111827),
          contentTextStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          behavior: SnackBarBehavior.fixed,
        ),
        dialogTheme: DialogTheme(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
          contentTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ),
      builder: (context, child) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
      ),
      routes: {
        '/terms': (_) => const TermsScreen(),
        '/privacy': (_) => const PrivacyPolicyScreen(),
      },
      home: FutureBuilder<void>(
        future: _appInitFuture,
        builder: (context, initSnap) {
          // Firebase 초기화 완료 전: 스플래시 표시
          if (initSnap.connectionState != ConnectionState.done) {
            return const _SplashScreen();
          }
          // 초기화 실패 시: 검은 화면 대신 스플래시 유지
          if (initSnap.hasError) {
            return const _SplashScreen();
          }
          // 초기화 완료 후: 인증 상태 감지
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _SplashScreen();
              }
              return const RoleGate();
            },
          );
        },
      ),
    );
  }
}

/// 앱 시작 시 Firebase 초기화 중 보여주는 스플래시 화면
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: const Image(
                image: AssetImage('assets/images/app_icon.png'),
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '페이모아',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: Color(0xFF7C3AED),
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showFatalSafely({
  required String title,
  required String message,
  StackTrace? st,
}) {
  if (_fatalHandling) {
    debugPrint('[FATAL][SKIP] $title: $message');
    return;
  }
  _fatalHandling = true;

  final body = '$message\n${st ?? ''}';
  debugPrint('[$title] $body');

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final ctx = _navKey.currentContext;
      if (ctx == null) {
        _fatalHandling = false;
        return;
      }

      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
        SnackBar(
          content: Text('$title: $message'),
          duration: const Duration(seconds: 4),
        ),
      );

      // ✅ 다이얼로그는 중복 방지
      if (_fatalDialogShowing) {
        _fatalHandling = false;
        return;
      }
      _fatalDialogShowing = true;

      await showDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      _fatalDialogShowing = false;
      _fatalHandling = false;
    } catch (e) {
      debugPrint('[FATAL][UI_FAIL] $e');
      _fatalDialogShowing = false;
      _fatalHandling = false;
    }
  });
}
