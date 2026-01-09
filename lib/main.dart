import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; // ✅ 추가

import 'ui/app_shell.dart';
// 알림 초기화는 일단 비활성(문제 분리용)
// import 'notifications/notification_planner.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 한국어 날짜 포맷 초기화
  await initializeDateFormatting('ko_KR', null);

  // 모든 Flutter 에러를 콘솔+UI로 노출 (앱 종료 방지)
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _showFatal('FlutterError', details.exceptionAsString(), details.stack);
  };

  runZonedGuarded(() async {
    runApp(const _SafeBootApp());

    // ⚠️ 알림 초기화는 잠시 중단 (원인 분리)
    // if (!kIsWeb) {
    //   try { await NotificationPlanner.instance.initialize(); } catch (e, st) {
    //     _showFatal('Notification init failed', '$e', st);
    //   }
    // }

    // 앱이 안정적으로 뜬 뒤 AppShell로 진입
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        _navKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const AppShell()),
        );
      } catch (e, st) {
        _showFatal('AppShell navigation failed', '$e', st);
      }
    });
  }, (error, stack) {
    _showFatal('Zoned error', '$error', stack);
  });
}

class _SafeBootApp extends StatelessWidget {
  const _SafeBootApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'PayCount (Safe Boot)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scaled = (mq.textScaleFactor * 1.12).clamp(1.0, 1.4);
        return MediaQuery(
          data: mq.copyWith(textScaleFactor: scaled.toDouble()),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _BootScreen(),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PayCount — 안전 부팅')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('초기화 중… 예외가 발생하면 다이얼로그로 표시됩니다.'),
          ],
        ),
      ),
    );
  }
}

void _showFatal(String title, String message, StackTrace? st) {
  final body = '$message\n${st ?? ''}';
  debugPrint('[$title] $body');

  // 앱이 올라와 있으면 UI로도 알림
  final ctx = _navKey.currentContext;
  if (ctx != null) {
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(
      SnackBar(content: Text('$title: $message'), duration: const Duration(seconds: 4)),
    );
    // 이미 다이얼로그가 떠 있을 수 있으니 안전하게 Future로 큐에 올림
    Future.microtask(() {
      final c = _navKey.currentContext;
      if (c == null) return;
      showDialog(
        context: c,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('확인')),
          ],
        ),
      );
    });
  }
}
