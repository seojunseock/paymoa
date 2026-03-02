// lib/ui/app_shell.dart
import 'dart:async';
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

// role (SharedPrefs)
import '../role/role_repository.dart';

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

  // ────────────────────────────────────────────────────────────────
  // ✅ [BUG FIX] 스트림을 build() 안에서 매번 새로 생성하면 리빌드마다
  //    Firestore 구독이 폭증한다. uid별로 캐시해서 한 번만 생성한다.
  // ────────────────────────────────────────────────────────────────
  String? _cachedUid;
  Stream<List<UICalendarAlba>>? _albasMergedStream;
  Stream<_JoinPolicyBundle>? _joinPolicyBundleStream;
  Stream<List<UICalendarSchedule>>? _schedulesStream;

  /// uid가 바뀐 경우에만 새 스트림을 만든다.
  void _initStreamsIfNeeded(String uid) {
    if (_cachedUid == uid) return;
    _cachedUid = uid;

    // activeJoins$ 를 한 번만 만들어 schedules 스트림에 전달
    final activeJoins$ = _firebaseService.watchActiveJoinPaths(uid);

    _albasMergedStream = _watchMyAlbasMerged(uid);
    _joinPolicyBundleStream = _watchJoinPolicyBundle(uid);
    _schedulesStream = _firebaseService.watchMySchedulesUiMergedV2(
      workerUid: uid,
      activeJoins$: activeJoins$,
      recentDays: 365,
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

      // ✅ 최초 1회만이 아닌 항상 동기화 (앱 재시작 없이 정책 반영)
      setState(() {
        for (final entry in policyMap.entries) {
          final albaId = entry.key;
          final policy = entry.value;

          final tax = pm.taxConfigFromPolicy(policy);
          final ins = pm.insuranceConfigFromPolicy(policy);
          final sur = pm.surchargePolicyFromPolicy(policy);

          // ✅ payrollPolicy도 복원
          PayrollPolicy? payroll;
          final rawPayroll = policy['payrollPolicy'];
          if (rawPayroll is Map) {
            try {
              payroll =
                  ppm.payrollPolicyFromMap(rawPayroll.cast<String, dynamic>());
            } catch (_) {}
          }

          // ✅ policyHistory 파싱
          final rawHist = policy['_policyHistory'];
          final hist = PolicyHistory.fromList(rawHist);

          final old = _overridesByAlbaId[albaId];
          _overridesByAlbaId[albaId] = (old ?? const _AlbaOverrides()).copyWith(
            inheritFromStore: false, // ✅ 개인 알바는 항상 자체 설정 사용
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

  // ─────────────────────────────────────────────
  // ✅ 알림 과호출 방지: debounce + signature + suspend
  // ─────────────────────────────────────────────
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
      } catch (_) {
        // silent
      }
    });
  }

  // ─────────────────────────────────────────────
  // storeJoins 정책 bundle
  // ─────────────────────────────────────────────
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
      final histByStoreId = <String, PolicyHistory>{}; // ✅ 정책 이력

      for (final d in snap.docs) {
        final m = d.data();

        final storeId = (m['storeId'] as String?) ?? '';
        if (storeId.isEmpty) continue;

        final st = (m['status'] as String?)?.trim().toLowerCase();
        if (st != null && st.isNotEmpty && st != 'active') continue;

        // ✅ 사장님이 saveWorkerSettings로 저장한 ownerSetting 우선 적용
        final ownerSetting =
            (m['ownerSetting'] as Map?)?.cast<String, dynamic>();

        // inherit: ownerSetting → storeJoins 순서로 우선
        final inherit = ownerSetting != null
            ? (ownerSetting['inheritFromStore'] as bool?) ??
                (m['inheritFromStore'] as bool?) ??
                true
            : (m['inheritFromStore'] as bool?) ?? true;
        inheritByStoreId[storeId] = inherit;

        // policy: ownerSetting이 있으면 ownerSetting['policy'] 우선
        final policy = (ownerSetting != null && ownerSetting['policy'] is Map)
            ? (ownerSetting['policy'] as Map).cast<String, dynamic>()
            : (m['policy'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};

        taxByStoreId[storeId] = pm.taxConfigFromPolicy(policy);
        insByStoreId[storeId] = pm.insuranceConfigFromPolicy(policy);
        surByStoreId[storeId] = pm.surchargePolicyFromPolicy(policy);

        // ✅ policyHistory 파싱 (storeJoins에 저장된 이력)
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

        // payDay: ownerSetting 우선
        final payDay =
            (_toInt(ownerSetting?['payDay']) ?? _toInt(m['payDay']) ?? 25)
                .clamp(1, 31);
        payrollByStoreId[storeId] = (rawPayroll != null)
            ? ppm.payrollPolicyFromMap(rawPayroll)
            : _fallbackPayrollPolicyByPayDay(payDay);
      }

      // ✅ policyHistory에서 시급 밴드 빌드 (날짜별 wageAt 정확성)
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

        // ✅ 1970-01-01 초기 밴드가 policyHistory에 직접 저장됨
        // previousHourlyWage 추가 로직 불필요
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
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true) {
      return bundle.taxByStoreId[alba.id] ?? pol.TaxConfig.none;
    }
    return pol.TaxConfig.none;
  }

  pol.InsuranceConfig _resolvedInsOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.insurance != null) {
      return ov.insurance!;
    }
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true) {
      return bundle.insByStoreId[alba.id] ?? const pol.InsuranceNone();
    }
    return const pol.InsuranceNone();
  }

  pol.SurchargePolicy _resolvedSurchargeOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.surcharge != null) {
      return ov.surcharge!;
    }
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true) {
      return bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
    }
    return const pol.SurchargePolicy();
  }

  /// ✅ 날짜별 가산정책 콜백 (computeMonthlySummary/Engine 전달용)
  pol.SurchargePolicy Function(DateTime)? _surchargeAtOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    // 개인 설정 알바: _AlbaOverrides.surchargeAt 사용
    if (ov != null && !ov.inheritFromStore) {
      if (ov.policyHistory.isEmpty) return null;
      return (date) => ov.surchargeAt(date) ?? const pol.SurchargePolicy();
    }
    // 매장 정책 상속: joinBundle.surchargeAt 사용
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true) {
      final hist = bundle.histByStoreId[alba.id];
      if (hist == null || hist.isEmpty) return null;
      final fallback =
          bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
      return (date) => hist.surchargeAt(date) ?? fallback;
    }
    return null;
  }

  /// ✅ 개인 알바(비조인)용 surchargeAt
  pol.SurchargePolicy Function(DateTime)? _personalSurchargeAtOf(
      String albaId) {
    final ov = _ov(albaId);
    if (ov == null || ov.policyHistory.isEmpty) return null;
    return (date) => ov.surchargeAt(date) ?? const pol.SurchargePolicy();
  }

  PayrollPolicy _resolvedPayrollPolicyOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.payrollPolicy != null) {
      return ov.payrollPolicy!;
    }
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true) {
      return bundle.payrollByStoreId[alba.id] ??
          _fallbackPayrollPolicyByPayDay(alba.payDay);
    }
    return _fallbackPayrollPolicyByPayDay(alba.payDay);
  }

  // ─────────────────────────────────────────────
  // 알바 리스트: join + personal merge
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // joinPath 찾기(매장 스케줄 경로 필요)
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // ✅ WorkEditor 연결 (AppNav로 통일)
  // ─────────────────────────────────────────────
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
          // ✅ [권한 가드] 조인 매장은 정책 수정 불가 (사장님만 가능)
          final targetAlba = albas.firstWhere(
            (a) => a.id == albaId,
            orElse: () => const UICalendarAlba(
                id: '', storeId: '', name: '', colorHex: '#9CA3AF',
                hourlyWage: 0, payDay: 25),
          );
          if (targetAlba.storeId.isNotEmpty) return;

          // ✅ 정책 변경 후 Firestore 재구독으로 policyHistory 자동 반영
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
        // ✅ 날짜 기반 시급: 근무 저장 시 날짜로 policyHistory 조회 → overrideHourlyWage 자동 결정
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

  // ─────────────────────────────────────────────
  // ✅ 알바 수정 → AlbaFormScreen (기존 데이터 로드)
  // ─────────────────────────────────────────────
  void _openEditAlbaForm({
    required UICalendarAlba alba,
    required _JoinPolicyBundle joinBundle,
    required List<UICalendarSchedule> schedules,
  }) {
    // ✅ [권한 가드] 조인 매장은 수정 화면 진입 불가 (사장님만 가능)
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
      selectedDates: {}, // 수정 모드에서 날짜 추가는 work_editor로
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
              // ① 개인 알바: 과거 스케줄 보호 후 새 시급 저장
              // ✅ effectiveFrom이 미래 날짜면 그 이전 스케줄에 기존 시급 고정
              final wageChanged = res.hourlyWage != alba.hourlyWage;
              final hasEffectiveFrom =
                  !res.wageOnlyToday && res.wageEffectiveFrom != null;

              if (wageChanged && hasEffectiveFrom) {
                final today = DateTime.now();
                final todayDate = DateTime(today.year, today.month, today.day);
                // ✅ 오늘부터 포함 → !isBefore
                if (!res.wageEffectiveFrom!.isBefore(todayDate)) {
                  await _firebaseService.bulkUpdateScheduleWage(
                    workerUid: user.uid,
                    albaId: alba.id,
                    newWage: alba.hourlyWage, // 기존 시급으로 과거 고정
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
              await _firebaseService.updatePersonalAlbaWithPolicy(
                uid: user.uid,
                albaId: alba.id,
                name: res.storeName.trim().isEmpty
                    ? '이름없음'
                    : res.storeName.trim(),
                hourlyWage: res.hourlyWage,
                // ✅ 변경 전 시급 + 시급 기준일 → policyHistory 날짜 정확
                previousHourlyWage: (res.hourlyWage != alba.hourlyWage)
                    ? alba.hourlyWage
                    : null,
                colorHex: res.colorHex,
                payDay: res.payDay,
                policy: policyMap,
                wageEffectiveFrom:
                    (!res.wageOnlyToday && res.wageEffectiveFrom != null)
                        ? res.wageEffectiveFrom
                        : null, // ✅ 시급 기준일
                policyEffectiveFrom: res.policyEffectiveFrom, // ✅ 정책 기준일
              );
            } else {
              // ② Join 알바: 시급 변경 시 과거 스케줄 보호 후 storeJoins 저장
              if (res.hourlyWage != alba.hourlyWage) {
                // ✅ effectiveFrom이 미래 날짜면 이전 스케줄에 기존 시급 고정
                final hasEffectiveFrom =
                    !res.wageOnlyToday && res.wageEffectiveFrom != null;
                if (hasEffectiveFrom) {
                  final today = DateTime.now();
                  final todayDate =
                      DateTime(today.year, today.month, today.day);
                  // ✅ 오늘부터 포함 → !isBefore
                  if (!res.wageEffectiveFrom!.isBefore(todayDate)) {
                    await _firebaseService.bulkUpdateScheduleWage(
                      workerUid: user.uid,
                      albaId: alba.id,
                      newWage: alba.hourlyWage, // 기존 시급으로 과거 고정
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
            }

            // ③ 시급이 바뀐 경우 → 해당 날짜 기준 스케줄에 overrideHourlyWage 일괄 적용
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

            // ③ 메모리 오버라이드도 업데이트 (즉시 반영)
            if (mounted) {
              // ✅ policyEffectiveFrom이 있으면 새 이력 항목을 메모리에도 반영
              final oldOv =
                  _overridesByAlbaId[alba.id] ?? const _AlbaOverrides();
              PolicyHistory newHist = oldOv.policyHistory;
              if (!isJoin &&
                  res.policyEffectiveFrom != null &&
                  res.surcharge != null) {
                final pm2 = res.surcharge!;
                final policyMap = pm.buildPolicyMap(
                  tax: res.tax,
                  insurance: res.ins,
                  surcharge: pm2,
                  payrollPolicy: res.payrollPolicy,
                );
                final entry = PolicyHistoryEntry.fromMap({
                  ...policyMap,
                  'effectiveFrom': '${res.policyEffectiveFrom!.year}-'
                      '${res.policyEffectiveFrom!.month.toString().padLeft(2, '0')}-'
                      '${res.policyEffectiveFrom!.day.toString().padLeft(2, '0')}',
                });
                if (entry != null) {
                  newHist = newHist.append(entry);
                }
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
              SnackBar(content: Text('저장 실패: $e')),
            );
          }
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 개인 알바 등록 → Firestore 저장
  // ─────────────────────────────────────────────
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
            // ✅ 신규 등록 시에도 세금·보험·수당·급여정책 함께 저장
            policy: pm.buildPolicyMap(
              tax: res.tax,
              insurance: res.ins,
              surcharge: res.surcharge,
              payrollPolicy: res.payrollPolicy,
            ),
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

  // ─────────────────────────────────────────────
  // 매장 코드 등록 -> Firestore 저장
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // wage history (로컬 캐시)
  // ─────────────────────────────────────────────
  int wageAt(String albaId, DateTime dateLocal, List<UICalendarAlba> albas,
      {Map<String, List<_WageBand>>? wageBandsByStoreId,
      Map<String, PolicyHistory>? histByStoreId}) {
    // ✅ joinBundle의 wageBands 우선 (policyHistory 기반 날짜별 정확한 시급)
    // ✅ 개인알바는 _overridesByAlbaId.policyHistory에서 wageBands 빌드
    List<_WageBand>? bands = wageBandsByStoreId?[albaId] ?? _wageBands[albaId];
    if (bands == null || bands.isEmpty) {
      // 개인알바: policyHistory에서 hourlyWage 이력 추출
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

        // ✅ 첫 밴드 이전 구간: previousHourlyWage로 선행 밴드 추가
        // (기준일 이전 신규 스케줄 추가 시 올바른 시급 반환)
        // ✅ 1970-01-01 초기 밴드가 저장됨 - previousHourlyWage 추가 불필요
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
    // 날짜가 첫 밴드보다 이전인 경우:
    // - previousHourlyWage 밴드(from=1970)가 있으면 그게 last에 들어가 있음 → 정확
    // - 없으면(처음 저장 시 previousHourlyWage 누락) → 현재 시급 말고 첫 밴드 wage 반환
    //   (첫 변경 이후의 시급을 이전에도 쓰는 것보다, 첫 밴드 값 그대로가 나음)
    // 1970-01-01 초기 밴드가 항상 저장되므로 last가 null인 경우는 거의 없음
    // 혹시 구 데이터(초기 밴드 없음)의 경우: 가장 오래된 밴드 wage 반환
    if (last == null && bands.isNotEmpty) {
      return bands.first.wage;
    }
    return last?.wage ?? alba.hourlyWage;
  }

  // ─────────────────────────────────────────────
  // Auth actions
  // ─────────────────────────────────────────────
  Future<void> _logout() async {
    _notiDebounce?.cancel();
    _notiDebounce = null;
    _lastNotiSignature = '';

    if (mounted) setState(() => _tab = 0);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await RoleRepository().clearRole(user.uid);
    }

    await AuthService.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final db = FirebaseFirestore.instance;

    // ① Firestore 데이터 전체 삭제
    try {
      for (final sub in [
        'myAlbas',
        'storeJoins',
        'schedules',
        'personalAlbaPolicies',
        'policies',
      ]) {
        await _deleteCollection(db.collection('users').doc(uid).collection(sub));
      }
      await db.collection('users').doc(uid).delete();
    } catch (_) {
      // Firestore 삭제 실패 시에도 Auth 삭제는 진행
    }

    // ② 카카오 연결 해제 (카카오로 로그인한 경우)
    try {
      await UserApi.instance.unlink();
    } catch (_) {
      // 카카오 로그인이 아닌 경우 무시
    }

    // ③ SharedPrefs 역할 삭제
    await RoleRepository().clearRole(uid);

    // ④ Firebase Auth 계정 삭제
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

  /// Firestore 컬렉션 전체 삭제 (100건씩 배치)
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(workerUid)
          .collection('storeJoins')
          .doc(albaId)
          .set(
        {'status': 'ended', 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
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

  // ─────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요합니다.\n(로그인 화면으로 연결하세요)')),
      );
    }

    // ✅ [BUG FIX] 매 rebuild마다 새 스트림 생성 → Firestore 구독 폭증 방지
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
                      // ✅ [권한 가드] 조인 매장은 수정 불가 (사장님만 가능)
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

                      // ✅ 확인 다이얼로그는 호출부(alba_start_screen)에서 이미 처리
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
                          SnackBar(content: Text('삭제 실패: $e')),
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
                    onBack: null, // 바텀탭 - 뒤로가기 없음
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
                    payDay: _preferredPayDay(albas),
                    onOpenTerms: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsScreen()),
                    ),
                    onOpenPrivacy: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen()),
                    ),
                    onOpenSupport: () => SupportDialog.show(context),
                    onLogout: () async {
                      try {
                        await _logout();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('로그아웃 실패: $e')),
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
                          SnackBar(content: Text('탈퇴 실패: $e')),
                        );
                      }
                    },
                  ),
                ];

                return Scaffold(
                  body: IndexedStack(index: _tab, children: pages),
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
  final PolicyHistory policyHistory; // ✅ 정책 변경 이력

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

  /// ✅ 날짜별 가산정책 - policyHistory 이력에서 찾고 없으면 현재 surcharge
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

  /// ✅ storeId별 시급 밴드 (policyHistory의 hourlyWage 항목에서 빌드)
  final Map<String, List<_WageBand>> wageBandsByStoreId; // ✅ 정책 변경 이력

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

  /// ✅ 날짜별 가산정책
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
