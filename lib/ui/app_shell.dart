// lib/ui/app_shell.dart
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../policies/policy_sheet.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;

import '../navigation/app_nav.dart';
import '../common/support_dialog.dart';
import '../models/ui_calendar_models.dart';
import '../models/alba_form_models.dart';

import '../policies/policies.dart' as pol;
import '../models/policy_history.dart';

import '../screens/alba_start_screen.dart';
import '../screens/alba_form_screen.dart';
import '../services/last_work_time_service.dart';
import '../screens/calendar_screen.dart';
import '../screens/work_editor_args.dart' as wargs;
import '../screens/my_info_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/terms_screen.dart';

import '../notifications/notification_planner.dart';

// payroll
import '../payroll/payroll.dart';

// repos
import '../data/firebase_service.dart';

// auth
import '../auth/auth_service.dart';

// mappers
import '../policies/policy_mapper.dart' as pm;
import '../payroll/payroll_policy_mapper.dart' as ppm;

// join sheet models
import '../screens/join_store_sheet.dart';

// role / consent
import '../role/role_repository.dart';
import '../role/consent_repository.dart';
import '../ads/ad_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  final _firebaseService = FirebaseService();

  // 로컬 캐시(미래 확장)
  final Map<String, List<_WageBand>> _wageBands = {};
  final Map<String, _AlbaOverrides> _overridesByAlbaId = {};

  // ✅ 개인 알바 정책 Firebase 복원용 구독
  StreamSubscription<Map<String, Map<String, dynamic>>>? _policyRestoreSub;

  String? _cachedUid;
  Stream<List<UICalendarAlba>>? _albasMergedStream;
  Stream<_JoinPolicyBundle>? _joinPolicyBundleStream;
  Stream<List<UICalendarSchedule>>? _schedulesStream;

  void _initStreamsIfNeeded(String uid) {
    if (_cachedUid == uid) return;
    _cachedUid = uid;

    final activeJoins$ = _firebaseService.watchActiveJoinPaths(uid);

    _albasMergedStream = _watchMyAlbasMerged(uid);
    _joinPolicyBundleStream = _watchJoinPolicyBundle(uid);
    _schedulesStream = _firebaseService.watchMySchedulesUiMergedV2(
      workerUid: uid,
      activeJoins$: activeJoins$,
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribePolicyRestore();
  }

  void _subscribePolicyRestore() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _policyRestoreSub = _firebaseService
        .watchMyPersonalAlbaPolicies(user.uid)
        .listen((policyMap) {
      if (!mounted) return;

      setState(() {
        for (final entry in policyMap.entries) {
          final albaId = entry.key;
          final policy = entry.value;

          final tax = pm.taxConfigFromPolicy(policy);
          final ins = pm.insuranceConfigFromPolicy(policy);
          final sur = pm.surchargePolicyFromPolicy(policy);

          PayrollPolicy? payroll;
          final rawPayroll = policy['payrollPolicy'];
          if (rawPayroll is Map) {
            try {
              payroll =
                  ppm.payrollPolicyFromMap(rawPayroll.cast<String, dynamic>());
            } catch (_) {}
          }

          final rawHist = policy['_policyHistory'];
          final hist = PolicyHistory.fromList(rawHist);

          final old = _overridesByAlbaId[albaId];
          _overridesByAlbaId[albaId] = (old ?? const _AlbaOverrides()).copyWith(
            inheritFromStore: false,
            tax: tax,
            insurance: ins,
            surcharge: sur,
            payrollPolicy: payroll,
            policyHistory: hist,
          );
        }
      });
    });
  }

  Future<T?> _push<T>(Widget page) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Timer? _notiDebounce;
  String _lastNotiSignature = '';
  bool _suspendNoti = false;

  String _buildNotiSignature({
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
  }) {
    final a = albas
        .map((x) => '${x.id}|${x.payDay}|${x.hourlyWage}|${x.colorHex}')
        .join(',');
    final s = schedules
        .map((x) =>
            '${x.id}|${x.albaId}|${x.year}${x.month}${x.day}|${x.startHour}${x.startMinute}|${x.endHour}${x.endMinute}|${x.breakMinutes}|${x.workType.name}|${x.overrideHourlyWage ?? ''}|${x.docPath ?? ''}')
        .join(',');
    return '$a##$s';
  }

  int _preferredPayDay(List<UICalendarAlba> albas) {
    if (albas.isEmpty) return 25;

    final Map<int, int> freq = {};
    for (final a in albas) {
      final day = a.payDay;
      freq[day] = (freq[day] ?? 0) + 1;
    }

    int bestDay = albas.first.payDay;
    int bestCnt = 0;
    freq.forEach((day, cnt) {
      if (cnt > bestCnt || (cnt == bestCnt && day < bestDay)) {
        bestDay = day;
        bestCnt = cnt;
      }
    });
    return bestDay;
  }

  void _rescheduleNotificationsDebounced({
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
  }) {
    if (_suspendNoti) return;

    final sig = _buildNotiSignature(albas: albas, schedules: schedules);
    if (sig == _lastNotiSignature) return;

    _notiDebounce?.cancel();
    _notiDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      if (_suspendNoti) return;

      final sig2 = _buildNotiSignature(albas: albas, schedules: schedules);
      if (sig2 == _lastNotiSignature) return;

      try {
        await NotificationPlanner.instance.scheduleAll(
          schedules: schedules,
          payDay: _preferredPayDay(albas),
          settings: const AlarmSettings(
            workStartOn: true,
            workEndOn: true,
            paydayOn: true,
            startLeadMinutes: 10,
            endLeadMinutes: 10,
            paydayLeadDays: 0,
          ),
        );
        _lastNotiSignature = sig2;
      } catch (_) {}
    });
  }

  Stream<_JoinPolicyBundle> _watchJoinPolicyBundle(String myUid) {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('storeJoins');

    return col.snapshots().map((snap) {
      final taxByStoreId = <String, pol.TaxConfig>{};
      final insByStoreId = <String, pol.InsuranceConfig>{};
      final surByStoreId = <String, pol.SurchargePolicy?>{};
      final payrollByStoreId = <String, PayrollPolicy>{};
      final inheritByStoreId = <String, bool>{};
      final histByStoreId = <String, PolicyHistory>{};

      for (final d in snap.docs) {
        final m = d.data();

        final storeId = (m['storeId'] as String?) ?? '';
        if (storeId.isEmpty) continue;

        final st = (m['status'] as String?)?.trim().toLowerCase();
        if (st != null && st.isNotEmpty && st != 'active') continue;

        final ownerSetting =
            (m['ownerSetting'] as Map?)?.cast<String, dynamic>();

        final inherit = ownerSetting != null
            ? (ownerSetting['inheritFromStore'] as bool?) ??
                (m['inheritFromStore'] as bool?) ??
                true
            : (m['inheritFromStore'] as bool?) ?? true;
        inheritByStoreId[storeId] = inherit;

        final policy = (ownerSetting != null && ownerSetting['policy'] is Map)
            ? (ownerSetting['policy'] as Map).cast<String, dynamic>()
            : (m['policy'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};

        taxByStoreId[storeId] = pm.taxConfigFromPolicy(policy);
        insByStoreId[storeId] = pm.insuranceConfigFromPolicy(policy);
        surByStoreId[storeId] = pm.surchargePolicyFromPolicy(policy);

        final rawHist = m['policyHistory'];
        final hist = PolicyHistory.fromList(rawHist);
        if (hist.isNotEmpty) histByStoreId[storeId] = hist;

        Map<String, dynamic>? rawPayroll;
        final raw1 = policy['payrollPolicy'];
        if (raw1 is Map) {
          rawPayroll = raw1.cast<String, dynamic>();
        } else {
          final raw2 = m['payrollPolicy'];
          if (raw2 is Map) rawPayroll = raw2.cast<String, dynamic>();
        }

        final payDay =
            (_toInt(ownerSetting?['payDay']) ?? _toInt(m['payDay']) ?? 25)
                .clamp(1, 31);
        payrollByStoreId[storeId] = (rawPayroll != null)
            ? ppm.payrollPolicyFromMap(rawPayroll)
            : _fallbackPayrollPolicyByPayDay(payDay);
      }

      final wageBandsByStoreId = <String, List<_WageBand>>{};
      for (final entry in histByStoreId.entries) {
        final histEntries = entry.value.entries
            .where((e) => e.rawPolicy['hourlyWage'] != null)
            .toList()
          ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
        if (histEntries.isEmpty) continue;

        final bands = histEntries
            .map((e) {
              final w = e.rawPolicy['hourlyWage'];
              final wage = (w is int)
                  ? w
                  : (w is num)
                      ? w.toInt()
                      : int.tryParse('$w') ?? 0;
              return _WageBand(from: e.effectiveFrom, wage: wage);
            })
            .where((b) => b.wage > 0)
            .toList();

        if (bands.isNotEmpty) wageBandsByStoreId[entry.key] = bands;
      }

      return _JoinPolicyBundle(
        taxByStoreId: taxByStoreId,
        insByStoreId: insByStoreId,
        surByStoreId: surByStoreId,
        payrollByStoreId: payrollByStoreId,
        inheritByStoreId: inheritByStoreId,
        histByStoreId: histByStoreId,
        wageBandsByStoreId: wageBandsByStoreId,
      );
    });
  }

  PayrollPolicy _fallbackPayrollPolicyByPayDay(int payDay) {
    final now = DateTime.now();
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: PayDateRule.nextMonthlyDay(payDay),
    );
  }

  _AlbaOverrides? _ov(String albaId) => _overridesByAlbaId[albaId];

  pol.TaxConfig _resolvedTaxOf(UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.tax != null) return ov.tax!;
    return bundle.taxByStoreId[alba.id] ?? pol.TaxConfig.none;
  }

  pol.InsuranceConfig _resolvedInsOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.insurance != null) {
      return ov.insurance!;
    }
    return bundle.insByStoreId[alba.id] ?? const pol.InsuranceNone();
  }

  pol.SurchargePolicy _resolvedSurchargeOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.surcharge != null) {
      return ov.surcharge!;
    }
    return bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
  }

  pol.SurchargePolicy Function(DateTime)? _surchargeAtOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore) {
      final storeHist = bundle.histByStoreId[alba.id];
      final fallback =
          bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
      if (ov.policyHistory.isEmpty) {
        if (storeHist == null || storeHist.isEmpty) return null;
        return (date) => storeHist.surchargeAt(date) ?? fallback;
      }
      return (date) {
        final ind = ov.surchargeAt(date);
        if (ind != null) return ind;
        return storeHist?.surchargeAt(date) ?? fallback;
      };
    }
    final hist = bundle.histByStoreId[alba.id];
    if (hist == null || hist.isEmpty) return null;
    final fallback =
        bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
    return (date) => hist.surchargeAt(date) ?? fallback;
  }

  pol.SurchargePolicy Function(DateTime)? _personalSurchargeAtOf(
      String albaId) {
    final ov = _ov(albaId);
    if (ov == null || ov.policyHistory.isEmpty) return null;
    return (date) => ov.surchargeAt(date) ?? const pol.SurchargePolicy();
  }

  pol.TaxConfig Function(DateTime)? _taxAtOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore) {
      final storeHist = bundle.histByStoreId[alba.id];
      final fallback = bundle.taxByStoreId[alba.id] ?? pol.TaxConfig.none;
      if (ov.policyHistory.isEmpty) {
        if (storeHist == null || storeHist.isEmpty) return null;
        return (date) => storeHist.taxAt(date) ?? fallback;
      }
      return (date) {
        final ind = ov.policyHistory.taxAt(date);
        if (ind != null) return ind;
        return storeHist?.taxAt(date) ?? fallback;
      };
    }
    final hist = bundle.histByStoreId[alba.id];
    if (hist == null || hist.isEmpty) return null;
    final fallback = bundle.taxByStoreId[alba.id] ?? pol.TaxConfig.none;
    return (date) => hist.taxAt(date) ?? fallback;
  }

  pol.InsuranceConfig Function(DateTime)? _insuranceAtOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore) {
      final storeHist = bundle.histByStoreId[alba.id];
      final fallback =
          bundle.insByStoreId[alba.id] ?? const pol.InsuranceNone();
      if (ov.policyHistory.isEmpty) {
        if (storeHist == null || storeHist.isEmpty) return null;
        return (date) => storeHist.insuranceAt(date) ?? fallback;
      }
      return (date) {
        final ind = ov.policyHistory.insuranceAt(date);
        if (ind != null) return ind;
        return storeHist?.insuranceAt(date) ?? fallback;
      };
    }
    final hist = bundle.histByStoreId[alba.id];
    if (hist == null || hist.isEmpty) return null;
    final fallback = bundle.insByStoreId[alba.id] ?? const pol.InsuranceNone();
    return (date) => hist.insuranceAt(date) ?? fallback;
  }

  PayrollPolicy _resolvedPayrollPolicyOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.payrollPolicy != null) {
      return ov.payrollPolicy!;
    }
    return bundle.payrollByStoreId[alba.id] ??
        _fallbackPayrollPolicyByPayDay(alba.payDay);
  }

  // ✅ 추가: MyInfoScreen에 넘길 최근 3개월 최종 실수령 합계
  List<MyInfoMonthlyNetPoint> _buildMyInfoMonthlyNetPoints({
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
    required _JoinPolicyBundle joinBundle,
  }) {
    final engine = const PayrollEngine();
    final now = DateTime.now();
    final points = <MyInfoMonthlyNetPoint>[];

    for (int offset = 2; offset >= 0; offset--) {
      final dt = DateTime(now.year, now.month - offset, 1);
      int monthNet = 0;

      for (final alba in albas) {
        final albaSchedules =
            schedules.where((s) => s.albaId == alba.id).toList(growable: false);

        final tax = _resolvedTaxOf(alba, joinBundle);
        final ins = _resolvedInsOf(alba, joinBundle);
        final sur = _resolvedSurchargeOf(alba, joinBundle);
        final payroll = _resolvedPayrollPolicyOf(alba, joinBundle);

        final summary = engine.summaryForDate(
          policy: payroll,
          alba: alba,
          schedules: albaSchedules,
          tax: tax,
          insurance: ins,
          surchargePolicy: sur,
          surchargeAt: _surchargeAtOf(alba, joinBundle),
          taxAt: _taxAtOf(alba, joinBundle),
          insuranceAt: _insuranceAtOf(alba, joinBundle),
          wageAt: (albaId, dateLocal) => wageAt(
            albaId,
            dateLocal,
            albas,
            wageBandsByStoreId: joinBundle.wageBandsByStoreId,
          ),
          anyDateInPeriod: dt,
        );

        monthNet += summary.net;
      }

      points.add(
        MyInfoMonthlyNetPoint(
          year: dt.year,
          month: dt.month,
          net: monthNet,
        ),
      );
    }

    return points;
  }

  Stream<List<UICalendarAlba>> _watchMyAlbasMerged(String uid) {
    final join$ = _firebaseService.watchMyAlbas(uid);
    final personal$ = _firebaseService.watchMyPersonalAlbas(uid);

    late StreamController<List<UICalendarAlba>> controller;
    StreamSubscription? subA;
    StreamSubscription? subB;

    var latestA = const <UICalendarAlba>[];
    var latestB = const <UICalendarAlba>[];

    void emit() {
      final map = <String, UICalendarAlba>{};
      for (final a in latestA) {
        if (a.id.trim().isEmpty) continue;
        map[a.id] = a;
      }
      for (final a in latestB) {
        if (a.id.trim().isEmpty) continue;
        map[a.id] = a;
      }

      final merged = map.values.toList()
        ..sort((x, y) => x.name.compareTo(y.name));
      controller.add(merged);
    }

    controller = StreamController<List<UICalendarAlba>>.broadcast(
      onListen: () {
        subA = join$.listen((v) {
          latestA = v;
          emit();
        });
        subB = personal$.listen((v) {
          latestB = v;
          emit();
        });
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );

    return controller.stream;
  }

  Future<_JoinPath?> _findJoinPathByStoreId({
    required String myUid,
    required String storeId,
  }) async {
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('storeJoins')
        .where('storeId', isEqualTo: storeId)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;

    final d = qs.docs.first.data();
    final st = (d['status'] as String?)?.trim().toLowerCase();
    if (st != null && st.isNotEmpty && st != 'active') return null;

    final ownerUid = (d['ownerUid'] as String?) ?? '';
    if (ownerUid.isEmpty) return null;

    final employmentId = (d['employmentId'] as String?)?.trim();
    final normalizedEmploymentId =
        (employmentId == null || employmentId.isEmpty) ? null : employmentId;

    return _JoinPath(
      ownerUid: ownerUid,
      storeId: storeId,
      employmentId: normalizedEmploymentId,
    );
  }

  Future<void> _openWorkEditor(
    wargs.WorkEditorArgs args, {
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
    required _JoinPolicyBundle joinBundle,
  }) async {
    setState(() => _suspendNoti = true);

    try {
      await AppNav.openWorkEditorSheet(
        context: context,
        args: args,
        albas: albas,
        schedules: schedules,
        getSurchargePolicy: (albaId) {
          final alba = albas.firstWhere((a) => a.id == albaId,
              orElse: () => const UICalendarAlba(
                  id: '',
                  storeId: '',
                  name: '',
                  colorHex: '#9CA3AF',
                  hourlyWage: 0,
                  payDay: 25));
          return _resolvedSurchargeOf(alba, joinBundle);
        },
        onAdd: (s) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');

          final storeId = s.albaId;
          final path =
              await _findJoinPathByStoreId(myUid: user.uid, storeId: storeId);

          if (path != null) {
            await _firebaseService.addOneFromUi(
              ownerUid: path.ownerUid,
              storeId: path.storeId,
              workerUid: user.uid,
              employmentId: path.employmentId,
              ui: s,
            );
            return;
          }

          await _firebaseService.addOneFromUi(
            workerUid: user.uid,
            employmentId: null,
            ui: s,
          );
        },
        onUpdate: (s) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');

          // 매장(albaId)이 바뀐 경우: 기존 스케줄 삭제 후 새 위치에 추가
          final original =
              schedules.where((x) => x.id == s.id).firstOrNull;
          if (original != null && original.albaId != s.albaId) {
            await _firebaseService.deleteScheduleSmart(
                workerUid: user.uid, ui: original);

            final newStoreId = s.albaId;
            final path = await _findJoinPathByStoreId(
                myUid: user.uid, storeId: newStoreId);
            if (path != null) {
              await _firebaseService.addOneFromUi(
                ownerUid: path.ownerUid,
                storeId: path.storeId,
                workerUid: user.uid,
                employmentId: path.employmentId,
                ui: s,
              );
            } else {
              await _firebaseService.addOneFromUi(
                workerUid: user.uid,
                employmentId: null,
                ui: s,
              );
            }
            return;
          }

          await _firebaseService.updateScheduleSmart(
              workerUid: user.uid, ui: s);
        },
        onDelete: (scheduleId) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');

          final hit = schedules.where((x) => x.id == scheduleId).toList();
          final s = hit.isNotEmpty ? hit.first : null;
          if (s == null) throw StateError('삭제할 스케줄을 찾지 못했어요.');

          await _firebaseService.deleteScheduleSmart(
              workerUid: user.uid, ui: s);
        },
        onUpdatePolicy: (albaId, res) async {
          final targetAlba = albas.firstWhere(
            (a) => a.id == albaId,
            orElse: () => const UICalendarAlba(
                id: '',
                storeId: '',
                name: '',
                colorHex: '#9CA3AF',
                hourlyWage: 0,
                payDay: 25),
          );
          if (targetAlba.storeId.isNotEmpty) return;

          setState(() {
            final old = _overridesByAlbaId[albaId];
            _overridesByAlbaId[albaId] =
                (old ?? const _AlbaOverrides()).copyWith(
              inheritFromStore: false,
              tax: res.tax,
              insurance: res.ins,
              surcharge: res.surcharge,
            );
          });
        },
        wageAt: (albaId, dateLocal) => wageAt(
          albaId,
          dateLocal,
          albas,
          wageBandsByStoreId: joinBundle.wageBandsByStoreId,
          histByStoreId: joinBundle.histByStoreId,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _suspendNoti = false);
      _rescheduleNotificationsDebounced(albas: albas, schedules: schedules);
    }
  }

  void _openEditAlbaForm({
    required UICalendarAlba alba,
    required _JoinPolicyBundle joinBundle,
    required List<UICalendarSchedule> schedules,
  }) {
    if (alba.storeId.isNotEmpty) return;

    final tax = _resolvedTaxOf(alba, joinBundle);
    final ins = _resolvedInsOf(alba, joinBundle);
    final sur = _resolvedSurchargeOf(alba, joinBundle);
    final payroll = _resolvedPayrollPolicyOf(alba, joinBundle);
    final ov = _ov(alba.id);
    final isJoin = alba.storeId.isNotEmpty;

    final initial = AlbaFormInitial(
      storeId: alba.storeId,
      storeName: alba.name,
      hourlyWage: alba.hourlyWage,
      tax: tax,
      insurance: ins,
      surcharge: sur,
      payrollPolicy: payroll,
      startHour24: 9,
      startMinute: 0,
      endHour24: 18,
      endMinute: 0,
      breakMinutes: 0,
      selectedDates: {},
      colorHex: alba.colorHex,
      payDay: alba.payDay,
      inheritFromStore: ov?.inheritFromStore ?? isJoin,
      storeDefaults: null,
    );

    _push<void>(
      AlbaFormScreen(
        existingSchedules: schedules,
        initial: initial,
        editingAlbaId: alba.id,
        onBack: () => Navigator.of(context).pop(),
        onSubmit: (res) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          Navigator.of(context).pop();

          try {
            if (!isJoin) {
              final wageChanged = res.hourlyWage != alba.hourlyWage;
              final hasEffectiveFrom =
                  !res.wageOnlyToday && res.wageEffectiveFrom != null;

              if (wageChanged && hasEffectiveFrom) {
                final today = DateTime.now();
                final todayDate = DateTime(today.year, today.month, today.day);
                if (!res.wageEffectiveFrom!.isBefore(todayDate)) {
                  await _firebaseService.bulkUpdateScheduleWage(
                    workerUid: user.uid,
                    albaId: alba.id,
                    newWage: alba.hourlyWage,
                    schedules: schedules,
                    fromDate: DateTime(1970),
                    untilDate: res.wageEffectiveFrom,
                  );
                }
              }

              final policyMap = pm.buildPolicyMap(
                tax: res.tax,
                insurance: res.ins,
                surcharge: res.surcharge,
                payrollPolicy: res.payrollPolicy,
              );
              final prevPolicyMap = pm.buildPolicyMap(
                tax: tax,
                insurance: ins,
                surcharge: sur,
                payrollPolicy: payroll,
              );
              await _firebaseService.updatePersonalAlbaWithPolicy(
                uid: user.uid,
                albaId: alba.id,
                name: res.storeName.trim().isEmpty
                    ? '이름없음'
                    : res.storeName.trim(),
                hourlyWage: res.hourlyWage,
                previousHourlyWage: (res.hourlyWage != alba.hourlyWage)
                    ? alba.hourlyWage
                    : null,
                colorHex: res.colorHex,
                payDay: res.payDay,
                policy: policyMap,
                previousPolicy: prevPolicyMap,
                wageEffectiveFrom:
                    (!res.wageOnlyToday && res.wageEffectiveFrom != null)
                        ? res.wageEffectiveFrom
                        : null,
                policyEffectiveFrom: res.policyEffectiveFrom,
                surchargeEffectiveFrom: res.surchargeEffectiveFrom,
              );
              await LastWorkTimeService.save(
                albaId: alba.id,
                startH: res.startHour24,
                startM: res.startMinute,
                endH: res.endHour24,
                endM: res.endMinute,
                breakMin: res.breakMinutes,
              );
            } else {
              if (res.hourlyWage != alba.hourlyWage) {
                final hasEffectiveFrom =
                    !res.wageOnlyToday && res.wageEffectiveFrom != null;
                if (hasEffectiveFrom) {
                  final today = DateTime.now();
                  final todayDate =
                      DateTime(today.year, today.month, today.day);
                  if (!res.wageEffectiveFrom!.isBefore(todayDate)) {
                    await _firebaseService.bulkUpdateScheduleWage(
                      workerUid: user.uid,
                      albaId: alba.id,
                      newWage: alba.hourlyWage,
                      schedules: schedules,
                      fromDate: DateTime(1970),
                      untilDate: res.wageEffectiveFrom,
                    );
                  }
                }

                final joinPath = await _findJoinPathByStoreId(
                  myUid: user.uid,
                  storeId: alba.storeId,
                );
                if (joinPath != null) {
                  await _firebaseService.updateJoinAlbaWage(
                    uid: user.uid,
                    ownerUid: joinPath.ownerUid,
                    storeId: alba.storeId,
                    hourlyWage: res.hourlyWage,
                  );
                }
              }

              if (res.colorHex != alba.colorHex) {
                final joinPath = await _findJoinPathByStoreId(
                  myUid: user.uid,
                  storeId: alba.storeId,
                );
                if (joinPath != null) {
                  await _firebaseService.updateJoinAlbaColorHex(
                    workerUid: user.uid,
                    ownerUid: joinPath.ownerUid,
                    storeId: alba.storeId,
                    colorHex: res.colorHex,
                  );
                }
              }
            }

            if (res.hourlyWage != alba.hourlyWage &&
                (res.wageOnlyToday || res.wageEffectiveFrom != null)) {
              await _firebaseService.bulkUpdateScheduleWage(
                workerUid: user.uid,
                albaId: alba.id,
                newWage: res.hourlyWage,
                schedules: schedules,
                todayOnly: res.wageOnlyToday,
                fromDate: res.wageOnlyToday ? null : res.wageEffectiveFrom,
              );
            }

            if (mounted) {
              final oldOv =
                  _overridesByAlbaId[alba.id] ?? const _AlbaOverrides();
              PolicyHistory newHist = oldOv.policyHistory;

              if (!isJoin && res.hourlyWage != alba.hourlyWage) {
                final oldEntry = PolicyHistoryEntry.fromMap({
                  'hourlyWage': alba.hourlyWage,
                  'effectiveFrom': '1970-01-01',
                });
                if (oldEntry != null) newHist = newHist.append(oldEntry);
                if (res.wageEffectiveFrom != null) {
                  final ef = res.wageEffectiveFrom!;
                  final newEntry = PolicyHistoryEntry.fromMap({
                    'hourlyWage': res.hourlyWage,
                    'effectiveFrom':
                        '${ef.year}-${ef.month.toString().padLeft(2, '0')}-${ef.day.toString().padLeft(2, '0')}',
                  });
                  if (newEntry != null) newHist = newHist.append(newEntry);
                }
              }

              // 가산정책 오늘 즉시 이력 항목
              if (!isJoin && res.surchargeEffectiveFrom != null) {
                final surEff = res.surchargeEffectiveFrom!;
                final effectiveSur =
                    res.surcharge ?? const pol.SurchargePolicy();
                final surEntryMap = pm.buildPolicyMap(
                  tax: res.policyEffectiveFrom != null ? tax : res.tax,
                  insurance: res.policyEffectiveFrom != null ? ins : res.ins,
                  surcharge: effectiveSur,
                  payrollPolicy: res.payrollPolicy,
                );
                final surEntry = PolicyHistoryEntry.fromMap({
                  ...surEntryMap,
                  'effectiveFrom': '${surEff.year}-'
                      '${surEff.month.toString().padLeft(2, '0')}-'
                      '${surEff.day.toString().padLeft(2, '0')}',
                });
                if (surEntry != null) newHist = newHist.append(surEntry);
              }

              // 세금·보험 다음달 이력 항목
              if (!isJoin && res.policyEffectiveFrom != null) {
                final polEff = res.policyEffectiveFrom!;
                final effectiveSur =
                    res.surcharge ?? const pol.SurchargePolicy();
                final policyEntryMap = pm.buildPolicyMap(
                  tax: res.tax,
                  insurance: res.ins,
                  surcharge: effectiveSur,
                  payrollPolicy: res.payrollPolicy,
                );
                final polEntry = PolicyHistoryEntry.fromMap({
                  ...policyEntryMap,
                  'effectiveFrom': '${polEff.year}-'
                      '${polEff.month.toString().padLeft(2, '0')}-'
                      '${polEff.day.toString().padLeft(2, '0')}',
                });
                if (polEntry != null) newHist = newHist.append(polEntry);
              }
              setState(() {
                _overridesByAlbaId[alba.id] = (oldOv).copyWith(
                  inheritFromStore: res.inheritFromStore,
                  tax: isJoin ? null : res.tax,
                  insurance: isJoin ? null : res.ins,
                  surcharge: isJoin ? null : res.surcharge,
                  payrollPolicy: isJoin ? null : res.payrollPolicy,
                  policyHistory: newHist,
                );
              });
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('저장 완료!')),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('저장에 실패했어요. 잠시 후 다시 시도해 주세요.')),
            );
          }
        },
      ),
    );
  }

  void _openAlbaFormLocal({
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
  }) {
    final now = DateTime.now();
    final initial = AlbaFormInitial(
      storeId: '',
      storeName: '',
      hourlyWage: 0,
      tax: pol.TaxConfig.none,
      insurance: const pol.InsuranceNone(),
      surcharge: null,
      payrollPolicy: PayrollPolicy(
        cycle: PayCycleType.monthly,
        startFrom: DateTime(now.year, now.month, now.day),
        monthlyStartDay: 1,
        payRule: const PayDateRule.nextMonthlyDay(25),
      ),
      startHour24: 9,
      startMinute: 0,
      endHour24: 18,
      endMinute: 0,
      breakMinutes: 0,
      selectedDates: {},
      colorHex: '#3B82F6',
      payDay: 25,
      inheritFromStore: false,
      storeDefaults: null,
    );

    _push<void>(
      AlbaFormScreen(
        existingSchedules: schedules,
        initial: initial,
        onBack: () => Navigator.of(context).pop(),
        onSubmit: (res) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          Navigator.of(context).pop();

          final albaId = await _firebaseService.addPersonalAlba(
            uid: user.uid,
            name: res.storeName.trim().isEmpty ? '이름없음' : res.storeName.trim(),
            hourlyWage: res.hourlyWage,
            colorHex: res.colorHex,
            payDay: res.payDay,
            policy: pm.buildPolicyMap(
              tax: res.tax,
              insurance: res.ins,
              surcharge: res.surcharge,
              payrollPolicy: res.payrollPolicy,
            ),
          );
          await LastWorkTimeService.save(
            albaId: albaId,
            startH: res.startHour24,
            startM: res.startMinute,
            endH: res.endHour24,
            endM: res.endMinute,
            breakMin: res.breakMinutes,
          );

          for (final dt in res.selectedDates) {
            final d = DateTime(dt.year, dt.month, dt.day);
            await _firebaseService.addOneFromUi(
              workerUid: user.uid,
              employmentId: null,
              ui: UICalendarSchedule(
                id: '',
                albaId: albaId,
                year: d.year,
                month: d.month,
                day: d.day,
                startHour: res.startHour24,
                startMinute: res.startMinute,
                endHour: res.endHour24,
                endMinute: res.endMinute,
                breakMinutes: res.breakMinutes,
                workType: WorkType.basic,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _onJoinSubmit(
    JoinStoreSheetResult sheet,
    String workerName,
    String? storeAliasName,
    AlbaFormResult form,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');

    final workerUid = user.uid;
    final store = sheet.store;

    final storeId = store.id;
    final ownerUid = store.ownerUid;
    if (storeId.isEmpty || ownerUid.isEmpty) {
      throw StateError('매장 정보를 확인할 수 없습니다.');
    }

    final db = FirebaseFirestore.instance;

    final joinRef = db
        .collection('users')
        .doc(workerUid)
        .collection('storeJoins')
        .doc(storeId);

    final workerRef = db
        .collection('users')
        .doc(ownerUid)
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerUid);

    final joinSnap = await joinRef.get();
    final alreadyJoined = joinSnap.exists;

    final storePolicySnapshot =
        (store.policy ?? <String, dynamic>{}).cast<String, dynamic>();
    final inherit = form.inheritFromStore;

    final aliasBase = (storeAliasName ?? form.storeName).trim();
    final storeNameSaved = aliasBase.isEmpty
        ? (store.name.trim().isEmpty ? '이름없음' : store.name.trim())
        : aliasBase;

    final resolvedPayDay =
        (inherit ? (store.payDay ?? form.payDay) : form.payDay).clamp(1, 31);
    final resolvedWage = inherit
        ? (store.defaultHourlyWage ?? form.hourlyWage)
        : form.hourlyWage;

    final joinPayload = <String, dynamic>{
      'storeId': storeId,
      'ownerUid': ownerUid,
      'storeName': storeNameSaved,
      'colorHex': inherit ? (store.colorHex ?? form.colorHex) : form.colorHex,
      'payDay': resolvedPayDay,
      'defaultHourlyWage': resolvedWage,
      'hourlyWage': resolvedWage,
      'inheritFromStore': inherit,
      'policy': storePolicySnapshot,
      'workerName': workerName.trim(),
      'status': 'active',
      'joinedAt': alreadyJoined
          ? (joinSnap.data()?['joinedAt'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!alreadyJoined) 'createdAt': FieldValue.serverTimestamp(),
    };

    final workerPayload = <String, dynamic>{
      'workerUid': workerUid,
      'status': 'active',
      'displayName': workerName.trim().isEmpty
          ? (user.displayName ?? '')
          : workerName.trim(),
      'inheritFromStore': inherit,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final schedulesCol = db
        .collection('users')
        .doc(ownerUid)
        .collection('stores')
        .doc(storeId)
        .collection('schedules');

    final now = DateTime.now();
    final batch = db.batch();

    batch.set(joinRef, joinPayload, SetOptions(merge: true));
    batch.set(workerRef, workerPayload, SetOptions(merge: true));

    for (final dt in form.selectedDates) {
      final d = DateTime(dt.year, dt.month, dt.day);
      final y = d.year, m = d.month, day = d.day;

      final dateKey = y * 10000 + m * 100 + day;
      final startMin = form.startHour24 * 60 + form.startMinute;

      final docRef = schedulesCol.doc();
      batch.set(docRef, <String, dynamic>{
        'workerUid': workerUid,
        'albaId': storeId,
        'year': y,
        'month': m,
        'day': day,
        'startHour': form.startHour24,
        'startMinute': form.startMinute,
        'endHour': form.endHour24,
        'endMinute': form.endMinute,
        'breakMinutes': form.breakMinutes,
        'workType': WorkType.basic.name,
        'overrideHourlyWage': null,
        'dateKey': dateKey,
        'startMin': startMin,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.fromDate(now),
      });
    }

    await batch.commit();
  }

  int wageAt(String albaId, DateTime dateLocal, List<UICalendarAlba> albas,
      {Map<String, List<_WageBand>>? wageBandsByStoreId,
      Map<String, PolicyHistory>? histByStoreId}) {
    List<_WageBand>? bands = wageBandsByStoreId?[albaId] ?? _wageBands[albaId];
    if (bands == null || bands.isEmpty) {
      final ov = _overridesByAlbaId[albaId];
      if (ov != null && ov.policyHistory.isNotEmpty) {
        final builtBands = ov.policyHistory.entries
            .where((e) => e.rawPolicy['hourlyWage'] != null)
            .map((e) {
              final w = e.rawPolicy['hourlyWage'];
              final wage = (w is int)
                  ? w
                  : (w is num)
                      ? w.toInt()
                      : int.tryParse('$w') ?? 0;
              return _WageBand(from: e.effectiveFrom, wage: wage);
            })
            .where((b) => b.wage > 0)
            .toList()
          ..sort((a, b) => a.from.compareTo(b.from));

        bands = builtBands;
      }
    }
    final alba = albas.firstWhere(
      (x) => x.id == albaId,
      orElse: () => const UICalendarAlba(
        id: '',
        storeId: '',
        name: '',
        colorHex: '#3B82F6',
        hourlyWage: 0,
        payDay: 25,
      ),
    );
    if (bands == null || bands.isEmpty) return alba.hourlyWage;

    final d0 = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
    _WageBand? last;
    for (final b in bands) {
      if (!b.from.isAfter(d0)) {
        last = b;
      } else {
        break;
      }
    }
    if (last == null && bands.isNotEmpty) {
      return bands.first.wage;
    }
    return last?.wage ?? alba.hourlyWage;
  }

  Future<void> _logout() async {
    _notiDebounce?.cancel();
    _notiDebounce = null;
    _lastNotiSignature = '';

    if (mounted) setState(() => _tab = 0);

    await AuthService.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final roleRepo = RoleRepository();
    final consentRepo = ConsentRepository();

    try {
      for (final sub in [
        'myAlbas',
        'storeJoins',
        'schedules',
        'personalAlbaPolicies',
        'policies',
      ]) {
        await _deleteCollection(
            db.collection('users').doc(uid).collection(sub));
      }
      await db.collection('users').doc(uid).delete();
    } catch (_) {}

    try {
      await UserApi.instance.unlink();
    } catch (_) {}

    await roleRepo.clearRole(uid);
    await consentRepo.clearConsent(uid);

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('보안을 위해 로그아웃 후 다시 로그인하고 탈퇴해 주세요.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _deleteCollection(CollectionReference col) async {
    const batchSize = 100;
    while (true) {
      final snap = await col.limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = col.firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }

  Future<void> _deleteAlbaFully({
    required String workerUid,
    required String albaId,
    required List<UICalendarSchedule> schedules,
  }) async {
    final path =
        await _findJoinPathByStoreId(myUid: workerUid, storeId: albaId);

    if (path != null) {
      await _firebaseService.leaveStore(workerUid: workerUid, storeId: albaId);
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(workerUid)
        .collection('myAlbas')
        .doc(albaId)
        .delete();

    final personalSchedules =
        schedules.where((s) => s.albaId == albaId).toList();
    for (final s in personalSchedules) {
      await _firebaseService.deleteScheduleSmart(workerUid: workerUid, ui: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요합니다.\n(로그인 화면으로 연결하세요)')),
      );
    }

    _initStreamsIfNeeded(user.uid);

    return StreamBuilder<List<UICalendarAlba>>(
      stream: _albasMergedStream,
      builder: (context, albaSnap) {
        final albas = albaSnap.data ?? const <UICalendarAlba>[];

        return StreamBuilder<_JoinPolicyBundle>(
          stream: _joinPolicyBundleStream,
          builder: (context, joinSnap) {
            final joinBundle = joinSnap.data ?? _JoinPolicyBundle.empty();

            return StreamBuilder<List<UICalendarSchedule>>(
              stream: _schedulesStream,
              builder: (context, schSnap) {
                final schedules = schSnap.data ?? const <UICalendarSchedule>[];

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _rescheduleNotificationsDebounced(
                    albas: albas,
                    schedules: schedules,
                  );
                });

                final pages = <Widget>[
                  AlbaStartScreen(
                    albas: albas,
                    schedules: schedules,
                    onBack: () {},
                    onGoToAlbaForm: () {
                      _openAlbaFormLocal(albas: albas, schedules: schedules);
                    },
                    onEditAlba: (albaId) {
                      final alba = albas.firstWhere(
                        (a) => a.id == albaId,
                        orElse: () => UICalendarAlba(
                          id: albaId,
                          name: '알 수 없음',
                          colorHex: '#6B7280',
                          hourlyWage: 0,
                          payDay: 25,
                        ),
                      );
                      if (alba.storeId.isNotEmpty) return;
                      _openEditAlbaForm(
                        alba: alba,
                        joinBundle: joinBundle,
                        schedules: schedules,
                      );
                    },
                    onOpenWorkEditor: (args) async {
                      await _openWorkEditor(
                        args,
                        albas: albas,
                        schedules: schedules,
                        joinBundle: joinBundle,
                      );
                    },
                    onDeleteSchedule: (scheduleId) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      final hit =
                          schedules.where((x) => x.id == scheduleId).toList();
                      final s = hit.isNotEmpty ? hit.first : null;
                      if (s == null) return;

                      await _firebaseService.deleteScheduleSmart(
                        workerUid: u.uid,
                        ui: s,
                      );
                    },
                    onDeleteAlba: (albaId) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      try {
                        await _deleteAlbaFully(
                          workerUid: u.uid,
                          albaId: albaId,
                          schedules: schedules,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('삭제 완료')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해 주세요.')),
                        );
                      }
                    },
                    onJoinSubmit: _onJoinSubmit,
                    getTaxPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    getInsurancePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    getSurchargePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    getSurchargeAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _surchargeAtOf(alba, joinBundle);
                    },
                    getTaxAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _taxAtOf(alba, joinBundle);
                    },
                    getInsuranceAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _insuranceAtOf(alba, joinBundle);
                    },
                    getPayrollPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedPayrollPolicyOf(alba, joinBundle);
                    },
                    getWageAt: (albaId, dateLocal) => wageAt(
                        albaId, dateLocal, albas,
                        wageBandsByStoreId: joinBundle.wageBandsByStoreId),
                  ),
                  CalendarScreen(
                    onBack: null,
                    albas: albas,
                    schedules: schedules,
                    onDeleteSchedule: (id) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      final hit = schedules.where((x) => x.id == id).toList();
                      final s = hit.isNotEmpty ? hit.first : null;
                      if (s == null) return;

                      await _firebaseService.deleteScheduleSmart(
                        workerUid: u.uid,
                        ui: s,
                      );
                    },
                    getTaxPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    getInsurancePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    getSurchargePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    getSurchargeAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _surchargeAtOf(alba, joinBundle);
                    },
                    getTaxAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _taxAtOf(alba, joinBundle);
                    },
                    getInsuranceAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _insuranceAtOf(alba, joinBundle);
                    },
                    getPayrollPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedPayrollPolicyOf(alba, joinBundle);
                    },
                    openWorkEditor: (args) async {
                      await _openWorkEditor(
                        args,
                        albas: albas,
                        schedules: schedules,
                        joinBundle: joinBundle,
                      );
                    },
                    wageAt: (albaId, dateLocal) => wageAt(
                        albaId, dateLocal, albas,
                        wageBandsByStoreId: joinBundle.wageBandsByStoreId),
                  ),
                  MyInfoScreen(
                    albas: albas,
                    schedules: schedules,
                    wageAt: (albaId, dateLocal) => wageAt(
                        albaId, dateLocal, albas,
                        wageBandsByStoreId: joinBundle.wageBandsByStoreId),
                    taxOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    insuranceOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    policyOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    surchargeAt: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId,
                          orElse: () => const UICalendarAlba(
                              id: '',
                              storeId: '',
                              name: '',
                              colorHex: '#9CA3AF',
                              hourlyWage: 0,
                              payDay: 25));
                      return _surchargeAtOf(alba, joinBundle);
                    },
                    // ✅ 추가: 마이 인포는 여기서 만든 최종 금액만 받음
                    monthlyNetPoints: _buildMyInfoMonthlyNetPoints(
                      albas: albas,
                      schedules: schedules,
                      joinBundle: joinBundle,
                    ),
                    payDay: _preferredPayDay(albas),
                    onOpenTerms: () => launchUrl(
                      Uri.parse('https://funky-mandevilla-5dc.notion.site/Terms-of-Service-9a7d10d5a0394f2a9cee324fe89893a7'),
                      mode: LaunchMode.externalApplication,
                    ),
                    onOpenPrivacy: () => launchUrl(
                      Uri.parse('https://funky-mandevilla-5dc.notion.site/Privacy-Policy-599f1871c09d40d782e5c1936444f6ac'),
                      mode: LaunchMode.externalApplication,
                    ),
                    onOpenSupport: () => SupportDialog.show(context),
                    onLogout: () async {
                      try {
                        await _logout();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('로그아웃에 실패했어요. 잠시 후 다시 시도해 주세요.')),
                        );
                      }
                    },
                    onDeleteAccount: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('정말 탈퇴하시겠어요?'),
                          content: const Text(
                            '탈퇴하면 모든 근무 기록, 알바 정보가\n완전히 삭제되며 복구할 수 없어요.',
                            style: TextStyle(height: 1.5),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소',
                                  style: TextStyle(color: Color(0xFF6B7280))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('탈퇴하기',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF43F5E))),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;

                      try {
                        await _deleteAccount();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('탈퇴에 실패했어요. 잠시 후 다시 시도해 주세요.')),
                        );
                      }
                    },
                  ),
                ];

                return Scaffold(
                  body: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        const AdBannerWidget(),
                        Expanded(child: IndexedStack(index: _tab, children: pages)),
                      ],
                    ),
                  ),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    backgroundColor: Colors.white,
                    indicatorColor: const Color(0xFF7C3AED).withOpacity(0.10),
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: const Icon(Icons.home_rounded,
                            color: Color(0xFF7C3AED)),
                        label: '홈',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.calendar_today_outlined),
                        selectedIcon: const Icon(Icons.calendar_today_rounded,
                            color: Color(0xFF7C3AED)),
                        label: '달력',
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.person_outline),
                        selectedIcon: const Icon(Icons.person_rounded,
                            color: Color(0xFF7C3AED)),
                        label: '내 정보',
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _policyRestoreSub?.cancel();
    _notiDebounce?.cancel();
    super.dispose();
  }
}

/* ───────────────────────────────────────────── */

class _JoinPath {
  final String ownerUid;
  final String storeId;
  final String? employmentId;

  _JoinPath({
    required this.ownerUid,
    required this.storeId,
    required this.employmentId,
  });
}

class _AlbaOverrides {
  final bool inheritFromStore;
  final pol.TaxConfig? tax;
  final pol.InsuranceConfig? insurance;
  final pol.SurchargePolicy? surcharge;
  final PayrollPolicy? payrollPolicy;
  final PolicyHistory policyHistory;

  const _AlbaOverrides({
    this.inheritFromStore = true,
    this.tax,
    this.insurance,
    this.surcharge,
    this.payrollPolicy,
    this.policyHistory = const PolicyHistory.empty_(),
  });

  _AlbaOverrides copyWith({
    bool? inheritFromStore,
    pol.TaxConfig? tax,
    pol.InsuranceConfig? insurance,
    pol.SurchargePolicy? surcharge,
    PayrollPolicy? payrollPolicy,
    PolicyHistory? policyHistory,
  }) {
    return _AlbaOverrides(
      inheritFromStore: inheritFromStore ?? this.inheritFromStore,
      tax: tax ?? this.tax,
      insurance: insurance ?? this.insurance,
      surcharge: surcharge ?? this.surcharge,
      payrollPolicy: payrollPolicy ?? this.payrollPolicy,
      policyHistory: policyHistory ?? this.policyHistory,
    );
  }

  pol.SurchargePolicy? surchargeAt(DateTime date) {
    if (policyHistory.isEmpty) return surcharge;
    return policyHistory.surchargeAt(date) ?? surcharge;
  }
}

class _WageBand {
  final DateTime from;
  final int wage;
  _WageBand({required this.from, required this.wage});
}

class _JoinPolicyBundle {
  final Map<String, pol.TaxConfig> taxByStoreId;
  final Map<String, pol.InsuranceConfig> insByStoreId;
  final Map<String, pol.SurchargePolicy?> surByStoreId;
  final Map<String, PayrollPolicy> payrollByStoreId;
  final Map<String, bool> inheritByStoreId;
  final Map<String, PolicyHistory> histByStoreId;
  final Map<String, List<_WageBand>> wageBandsByStoreId;

  const _JoinPolicyBundle({
    required this.taxByStoreId,
    required this.insByStoreId,
    required this.surByStoreId,
    required this.payrollByStoreId,
    required this.inheritByStoreId,
    this.histByStoreId = const {},
    this.wageBandsByStoreId = const {},
  });

  factory _JoinPolicyBundle.empty() => const _JoinPolicyBundle(
        taxByStoreId: {},
        insByStoreId: {},
        surByStoreId: {},
        payrollByStoreId: {},
        inheritByStoreId: {},
        histByStoreId: {},
      );

  pol.SurchargePolicy? surchargeAt(String storeId, DateTime date) {
    final hist = histByStoreId[storeId];
    if (hist == null || hist.isEmpty) return surByStoreId[storeId];
    return hist.surchargeAt(date) ?? surByStoreId[storeId];
  }
}

int? _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}
