// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'role/role_gate.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

bool _fatalHandling = false; // ✅ 에러 처리 중복/무한루프 방지
bool _fatalDialogShowing = false; // ✅ 다이얼로그 중복 방지

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await initializeDateFormatting('ko_KR', null);

    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details);

      _showFatalSafely(
        title: 'FlutterError',
        message: details.exceptionAsString(),
        st: details.stack,
      );
    };

    runApp(const _SafeBootApp());
  }, (error, stack) {
    _showFatalSafely(title: 'Zoned error', message: '$error', st: stack);
  });
}

class _SafeBootApp extends StatelessWidget {
  const _SafeBootApp();

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.light,
    );

    // ✅ 토스톤(톤다운)
    final cs = base.copyWith(
      primary: const Color(0xFF2563EB),
      primaryContainer: const Color(0xFFEAF2FF),
      onPrimaryContainer: const Color(0xFF0F172A),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF7F8FA),
      surfaceContainer: const Color(0xFFF4F6F8),
      outline: const Color(0x1F0F172A),
    );

    final radius = BorderRadius.circular(16);

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Paymoa',
      debugShowCheckedModeBanner: false,
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
          behavior: SnackBarBehavior.floating,
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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const RoleGate();
        },
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
