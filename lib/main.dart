// lib/main.dart
import 'package:flutter/material.dart';
import 'ui/app_shell.dart';

// 🔔 시스템 알림 엔진 초기화/사용
import 'notifications/notification_planner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) 로컬 알림 엔진 초기화(채널 생성, 타임존 세팅, iOS 권한 요청)
  await NotificationPlanner.instance.initialize();

  // (선택) 초기 안내 알림 – 권한 허용 후 상단바 표시 테스트용
  // await NotificationPlanner.instance.showNow(
  //   title: 'PayCount',
  //   body: '알림이 정상 수신됩니다.',
  // );

  runApp(const PayCountApp());
}

class PayCountApp extends StatelessWidget {
  const PayCountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PayCount',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      // 전 화면 글자 살짝 키우기(가독성)
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scaled = (mq.textScaleFactor * 1.12).clamp(1.0, 1.4);
        return MediaQuery(
          data: mq.copyWith(textScaleFactor: scaled.toDouble()),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }
}
