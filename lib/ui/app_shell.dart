// lib/ui/app_shell.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ui_calendar_models.dart';
import '../models/alba_form_models.dart';

import '../policies/policies.dart' as pol;

import '../screens/alba_start_screen.dart';
import '../screens/alba_form_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/work_editor_args.dart' as wargs;
import '../screens/work_editor_screen.dart'; // ✅ showWorkEditorSheet 사용
import '../screens/my_info_screen.dart';

import '../notifications/notification_planner.dart';

// payroll
import '../payroll/payroll.dart';

// repos
import '../data/my_store_join_repository.dart';
import '../data/schedule_repository.dart';
import '../data/my_personal_alba_repository.dart';

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

  final _joinRepo = MyStoreJoinRepository();
  final _personalAlbaRepo = MyPersonalAlbaRepository();
  final _scheduleRepo = ScheduleRepository();

  // 로컬 캐시
  final Map<String, List<_WageBand>> _wageBands = {};
  final Map<String, _AlbaOverrides> _overridesByAlbaId = {};

  Future<T?> _push<T>(Widget page) {
    return Navigator.of(context)
        .push<T>(MaterialPageRoute(builder: (_) => page));
  }

  // ─────────────────────────────────────────────
  // ✅ 알림 과호출 방지: debounce + signature + suspend
  // ─────────────────────────────────────────────
  Timer? _notiDebounce;
  String _lastNotiSignature = '';

  // ✅ 시트/탭 전환/편집 중에는 알림 스케줄링 잠깐 중지 (렉 방지)
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
    // ✅ 편집/시트/전환 중에는 스킵 (렉 방지)
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

      for (final d in snap.docs) {
        final m = d.data();

        final storeId = (m['storeId'] as String?) ?? '';
        if (storeId.isEmpty) continue;

        final st = (m['status'] as String?)?.trim().toLowerCase();
        if (st != null && st.isNotEmpty && st != 'active') continue;

        final inherit = (m['inheritFromStore'] as bool?) ?? true;
        inheritByStoreId[storeId] = inherit;

        final policy = (m['policy'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

        taxByStoreId[storeId] = pm.taxConfigFromPolicy(policy);
        insByStoreId[storeId] = pm.insuranceConfigFromPolicy(policy);
        surByStoreId[storeId] = pm.surchargePolicyFromPolicy(policy);

        Map<String, dynamic>? rawPayroll;
        final raw1 = policy['payrollPolicy'];
        if (raw1 is Map) {
          rawPayroll = raw1.cast<String, dynamic>();
        } else {
          final raw2 = m['payrollPolicy'];
          if (raw2 is Map) rawPayroll = raw2.cast<String, dynamic>();
        }

        final payDay = ((_toInt(m['payDay']) ?? 25)).clamp(1, 31);
        payrollByStoreId[storeId] = (rawPayroll != null)
            ? ppm.payrollPolicyFromMap(rawPayroll)
            : _fallbackPayrollPolicyByPayDay(payDay);
      }

      return _JoinPolicyBundle(
        taxByStoreId: taxByStoreId,
        insByStoreId: insByStoreId,
        surByStoreId: surByStoreId,
        payrollByStoreId: payrollByStoreId,
        inheritByStoreId: inheritByStoreId,
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
    if (inherit == true)
      return bundle.taxByStoreId[alba.id] ?? pol.TaxConfig.none;
    return pol.TaxConfig.none;
  }

  pol.InsuranceConfig _resolvedInsOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.insurance != null)
      return ov.insurance!;
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true)
      return bundle.insByStoreId[alba.id] ?? const pol.InsuranceNone();
    return const pol.InsuranceNone();
  }

  pol.SurchargePolicy _resolvedSurchargeOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.surcharge != null)
      return ov.surcharge!;
    final inherit = bundle.inheritByStoreId[alba.id];
    if (inherit == true)
      return bundle.surByStoreId[alba.id] ?? const pol.SurchargePolicy();
    return const pol.SurchargePolicy();
  }

  PayrollPolicy _resolvedPayrollPolicyOf(
      UICalendarAlba alba, _JoinPolicyBundle bundle) {
    final ov = _ov(alba.id);
    if (ov != null && !ov.inheritFromStore && ov.payrollPolicy != null)
      return ov.payrollPolicy!;
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
    final join$ = _joinRepo.watchMyAlbas(uid);
    final personal$ = _personalAlbaRepo.watchMyPersonalAlbas(uid);

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
  // ✅ WorkEditor 연결 (push 제거 → 바텀시트로)
  // ─────────────────────────────────────────────
  Future<void> _openWorkEditor(
    wargs.WorkEditorArgs args, {
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
    required _JoinPolicyBundle joinBundle,
  }) async {
    // ✅ 시트 열리는 동안 알림 스케줄링 중지(렉 방지)
    setState(() => _suspendNoti = true);

    try {
      await showWorkEditorSheet(
        context: context,
        args: args,
        albas: albas,
        schedules: schedules,
        getSurchargePolicy: (albaId) {
          final alba = albas.firstWhere((a) => a.id == albaId);
          return _resolvedSurchargeOf(alba, joinBundle);
        },
        onAdd: (s) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');

          final storeId = s.albaId;
          final path =
              await _findJoinPathByStoreId(myUid: user.uid, storeId: storeId);

          if (path != null) {
            await _scheduleRepo.addOneFromUi(
              ownerUid: path.ownerUid,
              storeId: path.storeId,
              workerUid: user.uid,
              employmentId: path.employmentId,
              ui: s,
            );
            return;
          }

          await _scheduleRepo.addOneFromUi(
            workerUid: user.uid,
            employmentId: null,
            ui: s,
          );
        },
        onUpdate: (s) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');
          await _scheduleRepo.updateScheduleSmart(workerUid: user.uid, ui: s);
        },
        onDelete: (scheduleId) async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw StateError('로그인이 필요합니다.');

          final hit = schedules.where((x) => x.id == scheduleId).toList();
          final s = hit.isNotEmpty ? hit.first : null;
          if (s == null) throw StateError('삭제할 스케줄을 찾지 못했어요.');

          await _scheduleRepo.deleteScheduleSmart(workerUid: user.uid, ui: s);
        },
        onUpdatePolicy: (albaId, res) async {
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
      );
    } finally {
      if (!mounted) return;
      setState(() => _suspendNoti = false);
      // ✅ 시트 닫힌 뒤에만 “idle”로 알림 갱신 재개
      _rescheduleNotificationsDebounced(albas: albas, schedules: schedules);
    }
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

          final albaId = await _personalAlbaRepo.addPersonalAlba(
            uid: user.uid,
            name: res.storeName.trim().isEmpty ? '이름없음' : res.storeName.trim(),
            hourlyWage: res.hourlyWage,
            colorHex: res.colorHex,
            payDay: res.payDay,
          );

          for (final dt in res.selectedDates) {
            final d = DateTime(dt.year, dt.month, dt.day);
            await _scheduleRepo.addOneFromUi(
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
    if (storeId.isEmpty || ownerUid.isEmpty)
      throw StateError('매장 정보를 확인할 수 없습니다.');

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
  int wageAt(String albaId, DateTime dateLocal, List<UICalendarAlba> albas) {
    final bands = _wageBands[albaId];
    if (bands == null || bands.isEmpty) {
      final a = albas.firstWhere(
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
      return a.hourlyWage;
    }
    final d0 = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
    _WageBand? last;
    for (final b in bands) {
      if (!b.from.isAfter(d0)) {
        last = b;
      } else {
        break;
      }
    }
    return last?.wage ?? albas.firstWhere((x) => x.id == albaId).hourlyWage;
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

    await RoleRepository().clearRole(user.uid);
    await user.delete();
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인')),
        ],
      ),
    );
    return r ?? false;
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
          .set({'status': 'ended', 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
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
      await _scheduleRepo.deleteScheduleSmart(workerUid: workerUid, ui: s);
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

    final activeJoins$ = _joinRepo.watchActiveJoinPaths(user.uid);

    return StreamBuilder<List<UICalendarAlba>>(
      stream: _watchMyAlbasMerged(user.uid),
      builder: (context, albaSnap) {
        final albas = albaSnap.data ?? const <UICalendarAlba>[];

        return StreamBuilder<_JoinPolicyBundle>(
          stream: _watchJoinPolicyBundle(user.uid),
          builder: (context, joinSnap) {
            final joinBundle = joinSnap.data ?? _JoinPolicyBundle.empty();

            return StreamBuilder<List<UICalendarSchedule>>(
              stream: _scheduleRepo.watchMySchedulesUiMergedV2(
                workerUid: user.uid,
                activeJoins$: activeJoins$,
                recentDays: 120,
              ),
              builder: (context, schSnap) {
                final schedules = schSnap.data ?? const <UICalendarSchedule>[];

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _rescheduleNotificationsDebounced(
                      albas: albas, schedules: schedules);
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('TODO: 알바 설정 편집(다음 단계)')),
                      );
                    },
                    onOpenWorkEditor: (args) async {
                      await _openWorkEditor(args,
                          albas: albas,
                          schedules: schedules,
                          joinBundle: joinBundle);
                    },
                    onDeleteSchedule: (scheduleId) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      final hit =
                          schedules.where((x) => x.id == scheduleId).toList();
                      final s = hit.isNotEmpty ? hit.first : null;
                      if (s == null) return;

                      await _scheduleRepo.deleteScheduleSmart(
                          workerUid: u.uid, ui: s);
                    },
                    onDeleteAlba: (albaId) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      final ok = await _confirm(
                        context,
                        '이 알바를 삭제할까요?\n\n- 개인 알바: 완전 삭제\n- 조인 알바: 그만둠 처리(내 화면에서 숨김)\n  * 사장님 기록은 그대로 남아요',
                      );
                      if (!ok) return;

                      try {
                        await _deleteAlbaFully(
                            workerUid: u.uid,
                            albaId: albaId,
                            schedules: schedules);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('삭제 완료')));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                      }
                    },
                    onJoinSubmit: _onJoinSubmit,
                    getTaxPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    getInsurancePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    getSurchargePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    getPayrollPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedPayrollPolicyOf(alba, joinBundle);
                    },
                  ),
                  CalendarScreen(
                    onBack: () => setState(() => _tab = 0),
                    albas: albas,
                    schedules: schedules,
                    onDeleteSchedule: (id) async {
                      final u = FirebaseAuth.instance.currentUser;
                      if (u == null) return;

                      final hit = schedules.where((x) => x.id == id).toList();
                      final s = hit.isNotEmpty ? hit.first : null;
                      if (s == null) return;

                      await _scheduleRepo.deleteScheduleSmart(
                          workerUid: u.uid, ui: s);
                    },
                    getTaxPolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    getInsurancePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    getSurchargePolicy: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    openWorkEditor: (args) async {
                      await _openWorkEditor(args,
                          albas: albas,
                          schedules: schedules,
                          joinBundle: joinBundle);
                    },
                    wageAt: (albaId, dateLocal) =>
                        wageAt(albaId, dateLocal, albas),
                  ),
                  MyInfoScreen(
                    albas: albas,
                    schedules: schedules,
                    wageAt: (albaId, dateLocal) =>
                        wageAt(albaId, dateLocal, albas),
                    taxOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedTaxOf(alba, joinBundle);
                    },
                    insuranceOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedInsOf(alba, joinBundle);
                    },
                    policyOf: (albaId) {
                      final alba = albas.firstWhere((a) => a.id == albaId);
                      return _resolvedSurchargeOf(alba, joinBundle);
                    },
                    payDay: _preferredPayDay(albas),
                    onOpenTerms: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('서비스 이용약관 화면으로 이동합니다.')),
                    ),
                    onOpenPrivacy: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('개인정보 처리방침 화면으로 이동합니다.')),
                    ),
                    onOpenFaq: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('FAQ 화면으로 이동합니다.')),
                    ),
                    onOpenSupport: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('고객센터 문의로 이동합니다.')),
                    ),
                    onLogout: () async {
                      final ok = await _confirm(
                          context, '로그아웃 하시겠어요?\n(데이터는 그대로 유지됩니다)');
                      if (!ok) return;

                      try {
                        await _logout();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('로그아웃 실패: $e')));
                      }
                    },
                    onDeleteAccount: () async {
                      final ok = await _confirm(
                          context, '회원탈퇴 하시겠어요?\n(“최근 로그인 필요”가 뜰 수 있어요)');
                      if (!ok) return;

                      try {
                        await _deleteAccount();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('탈퇴 실패: $e')));
                      }
                    },
                  ),
                ];

                return Scaffold(
                  body: IndexedStack(index: _tab, children: pages),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.home_outlined), label: '홈'),
                      NavigationDestination(
                          icon: Icon(Icons.calendar_today_outlined),
                          label: '달력'),
                      NavigationDestination(
                          icon: Icon(Icons.person_outline), label: '내 정보'),
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

  const _AlbaOverrides({
    this.inheritFromStore = true,
    this.tax,
    this.insurance,
    this.surcharge,
    this.payrollPolicy,
  });

  _AlbaOverrides copyWith({
    bool? inheritFromStore,
    pol.TaxConfig? tax,
    pol.InsuranceConfig? insurance,
    pol.SurchargePolicy? surcharge,
    PayrollPolicy? payrollPolicy,
  }) {
    return _AlbaOverrides(
      inheritFromStore: inheritFromStore ?? this.inheritFromStore,
      tax: tax ?? this.tax,
      insurance: insurance ?? this.insurance,
      surcharge: surcharge ?? this.surcharge,
      payrollPolicy: payrollPolicy ?? this.payrollPolicy,
    );
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

  const _JoinPolicyBundle({
    required this.taxByStoreId,
    required this.insByStoreId,
    required this.surByStoreId,
    required this.payrollByStoreId,
    required this.inheritByStoreId,
  });

  factory _JoinPolicyBundle.empty() => const _JoinPolicyBundle(
        taxByStoreId: {},
        insByStoreId: {},
        surByStoreId: {},
        payrollByStoreId: {},
        inheritByStoreId: {},
      );
}

int? _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}
