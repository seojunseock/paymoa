// lib/ui/app_shell.dart
import 'package:flutter/material.dart';

import '../data/in_memory_repository.dart';
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart' as pol;

import '../screens/alba_start_screen.dart';
import '../screens/alba_form_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/work_editor_args.dart' as wargs;
import '../screens/work_editor_screen.dart';

// ✅ 내 정보 화면 연결
import '../screens/my_info_screen.dart';

// ✅ 상단바 로컬 알림 예약기
import '../notifications/notification_planner.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final InMemoryRepository repo = InMemoryRepository();

  // 0: 홈, 1: 달력, 2: 내정보
  int _tab = 0;

  /// 알바별 마지막 폼 저장값(수정초기화용)
  final Map<String, _AlbaFormDefaults> _albaDefaults = {};

  /// 알바별 시급 히스토리 (포함 시작일 기준)
  final Map<String, List<_WageBand>> _wageBands = {};

  Future<T?> _push<T>(Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  // ---------------- 알림 스케줄링 공통 ----------------

  /// 여러 알바가 있는 경우 대표 급여일을 선택
  int _preferredPayDay(List<UICalendarAlba> albas) {
    if (albas.isEmpty) return 25;
    // 가장 많이 설정된 payDay를 사용(동률이면 가장 작은 값)
    final Map<int, int> freq = {};
    for (final a in albas) {
      freq[a.payDay] = (freq[a.payDay] ?? 0) + 1;
    }
    int bestDay = albas.first.payDay;
    int bestCnt = 0;
    freq.forEach((day, cnt) {
      if (cnt > bestCnt || (cnt == bestCnt && day < bestDay)) {
        bestDay = day; bestCnt = cnt;
      }
    });
    return bestDay;
  }

  Future<void> _rescheduleNotifications() async {
    await NotificationPlanner.instance.scheduleAll(
      schedules: repo.schedules,
      payDay: _preferredPayDay(repo.albas),
      settings: const AlarmSettings(
        // 기본값(내 정보 화면에서 다시 설정하면 거기가 우선)
        workStartOn: true,
        workEndOn: true,
        paydayOn: true,
        startLeadMinutes: 10,
        endLeadMinutes: 10,
        paydayLeadDays: 0,
      ),
    );
  }

  // ---------------- 화면 전환/에디터 ----------------

  void _openWorkEditor(wargs.WorkEditorArgs args) {
    _push<void>(
      WorkEditorScreen(
        args: args,
        albas: repo.albas,
        schedules: repo.schedules,
        getSurchargePolicy: (id) => repo.policyOf(id),
        onAdd: (s) async {
          setState(() => repo.addSchedule(s));
          await _rescheduleNotifications(); // 근무 추가 → 리스케줄
        },
        onUpdate: (s) async {
          setState(() => repo.updateSchedule(s));
          await _rescheduleNotifications(); // 근무 수정 → 리스케줄
        },
        onDelete: (id) async {
          setState(() => repo.deleteSchedule(id));
          await _rescheduleNotifications(); // 근무 삭제 → 리스케줄
        },
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _openAlbaForm() {
    _push<void>(
      AlbaFormScreen(
        existingSchedules: repo.schedules,
        onBack: () => Navigator.of(context).pop(),
        onSubmit: (res) async {
          final alba = UICalendarAlba(
            id: '',
            name: res.storeName,
            hourlyWage: res.hourlyWage,
            colorHex: res.colorHex,
            payDay: res.payDay,
          );

          setState(() {
            repo.addAlba(alba);
            final saved = repo.albas.last;

            repo.setPolicies(
              albaId: saved.id,
              tax: res.tax,
              insurance: res.insurance,
              surcharge: res.surcharge,
            );

            for (final d in res.selectedDates) {
              repo.addSchedule(
                UICalendarSchedule(
                  id: '',
                  albaId: saved.id,
                  year: d.year,
                  month: d.month,
                  day: d.day,
                  startHour: res.startHour24,
                  startMinute: res.startMinute,
                  endHour: res.endHour24,
                  endMinute: res.endMinute,
                  breakMinutes: res.breakMinutes,
                ),
              );
            }

            _albaDefaults[saved.id] = _AlbaFormDefaults.fromResult(res);

            // 시급 히스토리 baseline 등록
            _wageBands[saved.id] = [
              _WageBand(from: DateTime(1970, 1, 1), wage: res.hourlyWage),
            ];
          });

          // 알바/스케줄 추가되었으니 알림 리스케줄
          await _rescheduleNotifications();

          Navigator.of(context).pop();
          setState(() => _tab = 1); // 달력으로
        },
      ),
    );
  }

  AlbaFormInitial _initialForEdit(UICalendarAlba alba) {
    final d = _albaDefaults[alba.id];
    if (d != null) {
      return AlbaFormInitial(
        storeName: alba.name,
        hourlyWage: d.hourlyWage,
        tax: d.tax,
        insurance: d.insurance,
        surcharge: d.surcharge,
        startHour24: d.startHour24,
        startMinute: d.startMinute,
        endHour24: d.endHour24,
        endMinute: d.endMinute,
        breakMinutes: d.breakMinutes,
        selectedDates: d.selectedDates,
        colorHex: d.colorHex,
        payDay: d.payDay,
      );
    }
    return _inferInitialFromSchedules(alba);
  }

  AlbaFormInitial _inferInitialFromSchedules(UICalendarAlba alba) {
    final tax = repo.taxOf(alba.id) ?? pol.TaxConfig.none;
    final ins = repo.insuranceOf(alba.id) ?? const pol.InsuranceNone();
    final sur = repo.policyOf(alba.id);

    final my = repo.schedules.where((s) => s.albaId == alba.id).toList()
      ..sort((a, b) =>
          DateTime(b.year, b.month, b.day).compareTo(DateTime(a.year, a.month, a.day)));

    int sh = 9, sm = 0, eh = 18, em = 0, br = 0;
    if (my.isNotEmpty) {
      sh = my.first.startHour;
      sm = my.first.startMinute;
      eh = my.first.endHour;
      em = my.first.endMinute;
      br = my.first.breakMinutes;
    }
    final selected = my.map((s) => DateTime.utc(s.year, s.month, s.day)).toSet();

    return AlbaFormInitial(
      storeName: alba.name,
      hourlyWage: alba.hourlyWage,
      tax: tax,
      insurance: ins,
      surcharge: sur,
      startHour24: sh,
      startMinute: sm,
      endHour24: eh,
      endMinute: em,
      breakMinutes: br,
      selectedDates: selected,
      colorHex: alba.colorHex,
      payDay: alba.payDay,
    );
  }

  void _applyWageChange({
    required String albaId,
    required int oldWage,
    required int newWage,
    required DateTime fromLocal, // 포함
  }) {
    final list = _wageBands.putIfAbsent(albaId, () => <_WageBand>[]);
    final fromOnly = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);

    final sameIdx = list.indexWhere((b) => b.from == fromOnly);
    if (sameIdx >= 0) {
      list[sameIdx] = _WageBand(from: fromOnly, wage: newWage);
    } else {
      list.add(_WageBand(from: fromOnly, wage: newWage));
    }
    if (!list.any((b) => b.from.isBefore(fromOnly))) {
      list.add(_WageBand(from: DateTime(1970, 1, 1), wage: oldWage));
    }
    list.sort((a, b) => a.from.compareTo(b.from));
  }

  int wageAt(String albaId, DateTime dateLocal) {
    final bands = _wageBands[albaId];
    if (bands == null || bands.isEmpty) {
      final a = repo.albas.firstWhere(
        (x) => x.id == albaId,
        orElse: () => UICalendarAlba(id: '', name: '', colorHex: '#3B82F6', hourlyWage: 0, payDay: 25),
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
    return last?.wage ?? repo.albas.firstWhere((x) => x.id == albaId).hourlyWage;
  }

  void _openAlbaFormEdit(UICalendarAlba alba) {
    final initial = _initialForEdit(alba);

    _push<void>(
      AlbaFormScreen(
        existingSchedules: repo.schedules,
        initial: initial,
        editingAlbaId: alba.id, // 수정 진입 ID 전달
        onBack: () => Navigator.of(context).pop(),
        onSubmit: (res) async {
          setState(() {
            final idx = repo.albas.indexWhere((a) => a.id == alba.id);
            final oldWage = alba.hourlyWage;

            if (idx != -1) {
              repo.albas[idx] = UICalendarAlba(
                id: alba.id,
                name: res.storeName,
                hourlyWage: res.hourlyWage,
                colorHex: res.colorHex,
                payDay: res.payDay,
              );
            }
            // 정책 반영
            repo.setPolicies(
              albaId: alba.id,
              tax: res.tax,
              insurance: res.insurance,
              surcharge: res.surcharge,
            );

            // 새 선택 날짜 추가(중복 제외)
            for (final d in res.selectedDates) {
              final exists = repo.schedules.any((s) =>
                  s.albaId == alba.id &&
                  s.year == d.year &&
                  s.month == d.month &&
                  s.day == d.day);
              if (exists) continue;

              repo.addSchedule(
                UICalendarSchedule(
                  id: '',
                  albaId: alba.id,
                  year: d.year,
                  month: d.month,
                  day: d.day,
                  startHour: res.startHour24,
                  startMinute: res.startMinute,
                  endHour: res.endHour24,
                  endMinute: res.endMinute,
                  breakMinutes: res.breakMinutes,
                ),
              );
            }

            _albaDefaults[alba.id] = _AlbaFormDefaults.fromResult(res);

            // ★ 시급 변경 히스토리 반영(적용 시작일 포함 이후)
            if (res.hourlyWage != oldWage && res.wageEffectiveFrom != null) {
              _applyWageChange(
                albaId: alba.id,
                oldWage: oldWage,
                newWage: res.hourlyWage,
                fromLocal: res.wageEffectiveFrom!,
              );
            }
          });

          // 알바 정보(특히 payDay)나 스케줄이 바뀌었으므로 알림 리스케줄
          await _rescheduleNotifications();

          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildHome() {
    return AlbaStartScreen(
      albas: repo.albas,
      schedules: repo.schedules,
      onBack: () {},
      onGoToAlbaForm: _openAlbaForm,
      onEditAlba: (albaId) {
        final target = repo.albas.firstWhere((a) => a.id == albaId);
        _openAlbaFormEdit(target);
      },
      onOpenWorkEditor: _openWorkEditor,
      getTaxPolicy: (id) => repo.taxOf(id),
      getInsurancePolicy: (id) => repo.insuranceOf(id),
      getSurchargePolicy: (id) => repo.policyOf(id),
    );
  }

  Widget _buildCalendar() {
    return CalendarScreen(
      onBack: () => setState(() => _tab = 0),
      albas: repo.albas,
      schedules: repo.schedules,
      onDeleteSchedule: (id) async {
        setState(() => repo.deleteSchedule(id));
        await _rescheduleNotifications(); // 삭제 → 리스케줄
      },
      getTaxPolicy: (id) => repo.taxOf(id) ?? pol.TaxConfig.none,
      getInsurancePolicy: (id) => repo.insuranceOf(id) ?? const pol.InsuranceNone(),
      getSurchargePolicy: (id) => repo.policyOf(id) ?? const pol.SurchargePolicy(),
      openWorkEditor: _openWorkEditor,
      // ★ 월합계 계산 시 날짜별 시급 사용
      wageAt: wageAt,
    );
  }

  Widget _buildProfile() {
    return MyInfoScreen(
      albas: repo.albas,
      schedules: repo.schedules,
      wageAt: wageAt,
      taxOf: (id) => repo.taxOf(id) ?? pol.TaxConfig.none,
      insuranceOf: (id) => repo.insuranceOf(id) ?? const pol.InsuranceNone(),
      policyOf: (id) => repo.policyOf(id) ?? const pol.SurchargePolicy(),
      payDay: _preferredPayDay(repo.albas),
      // 액션 핸들러(필요 시 라우팅 연결)
      onEditProfile: () {},
      onLogout: () {},
      onDeleteAccount: () {},
      onOpenTerms: () {},
      onOpenPrivacy: () {},
      onOpenFaq: () {},
      onOpenSupport: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHome(),
      _buildCalendar(),
      _buildProfile(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: '달력'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '내 정보'),
        ],
      ),
    );
  }
}

class _AlbaFormDefaults {
  final String colorHex;
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  final int breakMinutes;
  final int payDay;
  final Set<DateTime> selectedDates; // UTC 00:00

  _AlbaFormDefaults({
    required this.colorHex,
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
    required this.breakMinutes,
    required this.payDay,
    required this.selectedDates,
  });

  factory _AlbaFormDefaults.fromResult(AlbaFormResult r) => _AlbaFormDefaults(
        colorHex: r.colorHex,
        hourlyWage: r.hourlyWage,
        tax: r.tax,
        insurance: r.insurance,
        surcharge: r.surcharge,
        startHour24: r.startHour24,
        startMinute: r.startMinute,
        endHour24: r.endHour24,
        endMinute: r.endMinute,
        breakMinutes: r.breakMinutes,
        payDay: r.payDay,
        selectedDates: r.selectedDates.toSet(),
      );
}

class _WageBand {
  final DateTime from; // 로컬 날짜 자정, 포함
  final int wage;
  _WageBand({required this.from, required this.wage});
}
