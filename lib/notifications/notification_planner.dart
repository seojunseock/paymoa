// lib/notifications/notification_planner.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// 타임존: 별칭 분리
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/ui_calendar_models.dart';

/// 알림 설정 값(내 정보 화면에서 사용자가 고른 오프셋)
class AlarmSettings {
  final bool workStartOn;     // 출근 알림 사용
  final bool workEndOn;       // 퇴근 알림 사용
  final bool paydayOn;        // 급여일 알림 사용
  final int startLeadMinutes; // 근무 시작 X분 전 (1~60)
  final int endLeadMinutes;   // 근무 종료 X분 전 (1~60)
  final int paydayLeadDays;   // 급여일 D-N일 전 (0~15, 0=당일)

  const AlarmSettings({
    required this.workStartOn,
    required this.workEndOn,
    required this.paydayOn,
    required this.startLeadMinutes,
    required this.endLeadMinutes,
    required this.paydayLeadDays,
  });

  AlarmSettings copyWith({
    bool? workStartOn,
    bool? workEndOn,
    bool? paydayOn,
    int? startLeadMinutes,
    int? endLeadMinutes,
    int? paydayLeadDays,
  }) {
    return AlarmSettings(
      workStartOn: workStartOn ?? this.workStartOn,
      workEndOn: workEndOn ?? this.workEndOn,
      paydayOn: paydayOn ?? this.paydayOn,
      startLeadMinutes: startLeadMinutes ?? this.startLeadMinutes,
      endLeadMinutes: endLeadMinutes ?? this.endLeadMinutes,
      paydayLeadDays: paydayLeadDays ?? this.paydayLeadDays,
    );
  }
}

/// 상단바 로컬 알림 예약기(안드로이드/아이오에스)
/// - 출근/퇴근: 각 스케줄의 시작/종료 시각에서 오프셋만큼 뺀 시각에 단건 예약
/// - 급여일: 알바(매장)별 payDay에서 D-N일 전 오전 9시로 예약.
///   같은 날짜에 여러 알바가 겹치면 **1건**으로 합쳐서 "급여일 D-N"만 표시.
/// - 오버나이트(다음날 퇴근) 자동 보정, 과거 시각은 스킵.
class NotificationPlanner {
  NotificationPlanner._();
  static final NotificationPlanner instance = NotificationPlanner._();

  final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'paycount_default',
    'PayCount 기본 알림',
    description: '근무/급여일 알림',
    importance: Importance.high,
  );

  bool _initialized = false;

  /// 앱 시작 시 1회 호출(타임존/권한/채널 초기화)
  Future<void> initialize() async {
    if (_initialized) return;

    // 타임존 초기화
    tzdata.initializeTimeZones();

    // Android & iOS 초기화
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);

    await _flnp.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        if (kDebugMode) {
          debugPrint('Notification tapped: ${resp.payload}');
        }
      },
    );

    // 안드로이드 채널 생성(존재해도 안전)
    await _flnp
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  /// 전 예약 취소 후, 현재 데이터/설정 기준으로 다시 예약 (핵심 진입점)
  ///
  /// - 기존과의 호환을 위해 [payDay]는 선택값.
  /// - [albas]가 전달되면 **알바별 payDay**로 계산하고, 없으면 [payDay]를 사용.
  Future<void> scheduleAll({
    required List<UICalendarSchedule> schedules,
    List<UICalendarAlba>? albas,
    int? payDay, // fallback
    required AlarmSettings settings,
  }) async {
    await initialize();

    // 입력값 가드(UX에서 제한하지만 안전망)
    final leadStart = settings.startLeadMinutes.clamp(1, 60);
    final leadEnd = settings.endLeadMinutes.clamp(1, 60);
    final leadPay = settings.paydayLeadDays.clamp(0, 15);

    // 전량 취소(중복 방지)
    await _flnp.cancelAll();

    // ----- 출근/퇴근 (매장명 포함) -----
    final Map<String, String> albaNameById = {
      for (final a in (albas ?? const <UICalendarAlba>[])) a.id: a.name
    };

    if (settings.workStartOn || settings.workEndOn) {
      for (final s in schedules) {
        final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
        var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
        if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // 오버나이트
        final store = albaNameById[s.albaId];
        final startTitle = store == null ? '출근 알림' : '출근 알림 · $store';
        final endTitle = store == null ? '퇴근 알림' : '퇴근 알림 · $store';

        if (settings.workStartOn) {
          final when = start.subtract(Duration(minutes: leadStart));
          await _zonedOnce(
            id: _makeId('S', s.id),
            scheduledAt: when,
            title: startTitle,
            body: _fmtWorkBody(target: start, leadMinutes: leadStart, isStart: true),
            payload: 'work_start:${s.id}',
          );
        }

        if (settings.workEndOn) {
          final when = end.subtract(Duration(minutes: leadEnd));
          await _zonedOnce(
            id: _makeId('E', s.id),
            scheduledAt: when,
            title: endTitle,
            body: _fmtWorkBody(target: end, leadMinutes: leadEnd, isStart: false),
            payload: 'work_end:${s.id}',
          );
        }
      }
    }

    // ----- 급여일 (알바별) -----
    if (settings.paydayOn) {
      // 알바별 payDay 목록 산출(없으면 fallback payDay 사용)
      final List<int> payDays;
      if (albas != null && albas.isNotEmpty) {
        payDays = albas.map((a) => a.payDay).toList();
      } else if (payDay != null) {
        payDays = <int>[payDay];
      } else {
        payDays = const <int>[];
      }

      if (payDays.isNotEmpty) {
        final now = DateTime.now();
        final monthsToPlan = 3;

        for (int i = 0; i < monthsToPlan; i++) {
          final ym = DateTime(now.year, now.month + i, 1);

          // 같은 날로 모으기: yyyy-MM-dd 키 → 오전 9시 DateTime
          final Map<String, DateTime> uniqueDays = {};

          for (final d in payDays) {
            final realPayday = _safePaydayDate(ym.year, ym.month, d);
            final alertDay = realPayday.subtract(Duration(days: leadPay));
            final when = DateTime(alertDay.year, alertDay.month, alertDay.day, 9, 0);
            final key = _ymdKey(when);
            // 같은 날짜에 여러 알바가 겹치면 1건만 유지
            uniqueDays[key] = when;
          }

          for (final entry in uniqueDays.entries) {
            final when = entry.value;
            await _zonedOnce(
              id: _makeId('P', entry.key), // PAY-YYYYMMDD 고유화
              scheduledAt: when,
              title: '급여일 알림',
              body: leadPay == 0 ? '오늘은 급여일이에요' : '급여일 D-$leadPay',
              payload: 'payday:${_ymKey(ym)}',
            );
          }
        }
      }
    }
  }

  /// 즉시 표시(디버그용)
  Future<void> showNow({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    await _flnp.show(
      _randSmallId(),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// 모든 예약 취소
  Future<void> cancelAll() async {
    await _flnp.cancelAll();
  }

  // ---------------- 내부 유틸 ----------------

  /// 주어진 로컬 DateTime을 TZDateTime으로 예약(과거면 스킵)
  Future<void> _zonedOnce({
    required int id,
    required DateTime scheduledAt,
    required String title,
    required String body,
    String? payload,
  }) async {
    final now = DateTime.now();
    if (!scheduledAt.isAfter(now)) {
      if (kDebugMode) debugPrint('Skip past schedule: $scheduledAt');
      return;
    }
    final tzTime = tz.TZDateTime.from(scheduledAt, tz.local);

    await _flnp.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null, // 단건 예약
      payload: payload,
    );
  }

  // 알림 문구(목표 시각과 오프셋 기반)
  String _fmtWorkBody({
    required DateTime target,
    required int leadMinutes,
    required bool isStart,
  }) {
    final hh = target.hour.toString().padLeft(2, '0');
    final mm = target.minute.toString().padLeft(2, '0');
    return isStart
        ? '근무 시작 ${leadMinutes}분 전 · 예정 $hh:$mm'
        : '근무 종료 ${leadMinutes}분 전 · 예정 $hh:$mm';
  }

  DateTime _safePaydayDate(int year, int month, int payDay) {
    final last = DateUtils.getDaysInMonth(year, month);
    final day = min(payDay, last);
    return DateTime(year, month, day);
  }

  String _ymdKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _ymKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  // 스케줄/유형 기반 고유 int ID 생성(충돌 방지)
  int _makeId(String prefix, String raw) {
    final h = raw.hashCode & 0x7fffffff;
    final p = prefix.codeUnitAt(0) & 0xff;
    return (p << 24) | (h & 0x00ffffff);
  }

  int _randSmallId() => Random().nextInt(0x7fffffff);
}
