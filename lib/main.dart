// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'firebase_options.dart';
import 'role/role_gate.dart';
import 'screens/terms_screen.dart';
import 'screens/privacy_policy_screen.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

bool _fatalHandling = false;
bool _fatalDialogShowing = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    // timeout이든 에러든 무시하고 계속 진행
  }

  try {
    await initializeDateFormatting('ko_KR', null);
  } catch (_) {}

  try {
    KakaoSdk.init(nativeAppKey: '53dfe716642af3a731da9865a25e5db6');
  } catch (_) {}

  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C3AED),
      brightness: Brightness.light,
    );

    final cs = base.copyWith(
      primary: const Color(0xFF7C3AED),
      primaryContainer: const Color(0xFFF3EEFF),
      onPrimaryContainer: const Color(0xFF3B0764),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8F7FF),
      surfaceContainer: const Color(0xFFF4F0FF),
      outline: const Color(0x1F0F172A),
    );

    final radius = BorderRadius.circular(16);

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Paymoa',
      debugShowCheckedModeBanner: false,
      color: Colors.white,
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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }
          return const RoleGate();
        },
      ),
    );
  }
}


class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator()),
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
