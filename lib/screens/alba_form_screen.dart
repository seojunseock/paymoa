import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../common/app_words.dart';
import '../models/ui_calendar_models.dart';
import '../models/alba_form_models.dart';
import '../policies/policies.dart' as pol;
import '../policies/policy_sheet.dart';
import '../common/common_pickers.dart' as cp;
import 'date_assign_sheet.dart';

// payroll
import '../payroll/payroll.dart';
import 'payroll_policy_sheet.dart'; // ✅ 추가

class AlbaFormScreen extends StatefulWidget {
  const AlbaFormScreen({
    super.key,
    required this.existingSchedules,
    this.initial,
    this.editingAlbaId,
    required this.onBack,
    required this.onSubmit,
  });

  final List<UICalendarSchedule> existingSchedules;
  final AlbaFormInitial? initial;
  final String? editingAlbaId;

  final VoidCallback onBack;
  final void Function(AlbaFormResult result) onSubmit;

  @override
  State<AlbaFormScreen> createState() => _AlbaFormScreenState();
}

class _AlbaFormScreenState extends State<AlbaFormScreen> {
  final _name = TextEditingController(); // 매장 별칭
  final _workerNameCtrl = TextEditingController(); // 신규 조인: 본인 이름

  final _wage = TextEditingController(text: '');
  final _wageFocus = FocusNode();
  bool _formattingWage = false;

  // ✅ 수정 모드에서 초기 시급 (금액 변동 감지용)
  int? _initialWage;

  String _colorHex = '#3B82F6';
  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy? _surcharge;

  int _startH = 9, _startM = 0;
  int _endH = 18, _endM = 0;
  int _breakMin = 0;

  Set<DateTime> _selected = {};
  Set<DateTime> _existingDatesOfEditingAlbaUtc = {};

  bool _showPalette = false;
  bool _weeklyHoliday = false; // ✅ 주휴수당 - 근무시간 카드에서 독립 관리
  bool _weeklyOvertime = false; // ✅ 주 40시간 초과 연장수당

  pol.SurchargePolicy? _initialSurcharge; // ✅ 수정 모드 초기 정책 (변경 감지용)
  bool? _initialWeeklyHoliday;
  bool? _initialWeeklyOvertime;

  late PayrollPolicy _payrollPolicy;

  // ✅ 급여정책 “사용자 확정 여부”
  bool _payrollConfirmed = false;

  String _storeId = '';
  bool _inheritFromStore = true;
  AlbaStoreDefaultsSnapshot? _storeDefaults;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    // ✅ 기본값은 잡되, “확정 여부”는 별도로 관리
    _payrollPolicy = PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(10),
    );
    _payrollConfirmed = false; // ✅ 개인 알바 생성이면 기본 false로 시작

    _wage.addListener(() {
      if (_formattingWage) return;
      final txt = _wage.text;
      final formatted = _formatMoneyText(txt);
      if (formatted != txt) {
        _formattingWage = true;
        _wage.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        _formattingWage = false;
      }
    });

    final i = widget.initial;
    if (i != null) {
      _storeId = i.storeId;

      // ✅ 알바 화면에서는 “이름” 칸을 실제로 '매장 이름(별칭)'로 쓰는 구조였음
      _name.text = i.storeName;

      _wage.text = _commaInt(i.hourlyWage);
      _colorHex = i.colorHex;

      // ✅ 수정 모드에서 초기 시급 저장
      if (widget.editingAlbaId != null) {
        _initialWage = i.hourlyWage;
      }

      _tax = i.tax;
      _ins = i.insurance;
      _surcharge = i.surcharge;
      _weeklyHoliday = i.surcharge?.weeklyHolidayEnabled ?? false;
      _weeklyOvertime = (i.surcharge?.overtimeEnabled ?? false) &&
          (i.surcharge?.overtimeRule == pol.OvertimeRule.weeklyOver40);

      // ✅ 수정 모드 초기 정책 저장
      if (widget.editingAlbaId != null) {
        _initialSurcharge = i.surcharge;
        _initialWeeklyHoliday = _weeklyHoliday;
        _initialWeeklyOvertime = _weeklyOvertime;
      }

      _startH = i.startHour24;
      _startM = i.startMinute;
      _endH = i.endHour24;
      _endM = i.endMinute;
      _breakMin = i.breakMinutes;

      _selected = {...i.selectedDates};

      _inheritFromStore = i.inheritFromStore;
      _storeDefaults = i.storeDefaults;

      final sd = _storeDefaults;

      // ✅ storeDefaults가 있으면 그걸 최우선
      if (sd != null) {
        _payrollPolicy = sd.payrollPolicy;
        _payrollConfirmed = true; // ✅ 매장 정책이므로 “설정됨” 취급
      } else if (i.payrollPolicy != null) {
        _payrollPolicy = i.payrollPolicy!;
        _payrollConfirmed = true; // ✅ initial로 들어온 정책이 있으면 “설정됨”
      } else {
        // initial은 있는데 payrollPolicy가 없다? (예외) → 확정 false
        _payrollConfirmed = false;
      }
    }

    if (widget.editingAlbaId != null) {
      _existingDatesOfEditingAlbaUtc = widget.existingSchedules
          .where((s) => s.albaId == widget.editingAlbaId)
          .map((s) => DateTime.utc(s.year, s.month, s.day))
          .toSet();
    }

    // ✅ inherit ON + storeDefaults 있으면 정책 적용 + 확정 true
    if (_inheritFromStore && _storeDefaults != null) {
      _applyStoreDefaultsToFields(_storeDefaults!);
      _payrollPolicy = _storeDefaults!.payrollPolicy;
      _payrollConfirmed = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _workerNameCtrl.dispose();
    _wage.dispose();
    _wageFocus.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.editingAlbaId != null;

  /// ✅ Join 알바 수정 중 → 시급만 편집 가능, 정책은 잠금
  bool get _isJoinEdit => _isEdit && _storeId.isNotEmpty;

  Color get _color => cp.parseColor(_colorHex);
  String _fmtAmPm(int h, int m) => cp.fmtAmPm(h, m);

  String _ymd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _fmtYmdLocal(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  bool get _canShowInheritToggle =>
      _storeId.isNotEmpty && _storeDefaults != null;

  /// ✅ Join 알바 = 매장 소속 → 사장님만 설정 가능, 알바생은 시급/정책 모두 잠금
  bool get _lockStoreFields =>
      (_canShowInheritToggle && _inheritFromStore) || _isJoinEdit;

  /// 정책 잠금 = 매장설정 그대로 OR 조인 알바
  bool get _lockPolicyFields => _lockStoreFields;

  String _payrollSummaryLine(PayrollPolicy p) {
    String typeLabel() {
      if (p.cycle == PayCycleType.daily) return '일급';
      if (p.cycle == PayCycleType.monthly) {
        final s = (p.monthlyStartDay ?? 1).clamp(1, 31);
        if (s == 1) return '월급 (1일~말일)';
        return '월급 (매달 $s일 시작)';
      }
      if (p.cycle == PayCycleType.weekly) return '주급';
      if (p.cycle == PayCycleType.twoWeeks) return '2주';
      if (p.cycle == PayCycleType.customDays)
        return '${p.customEveryDays ?? 0}일';
      return AppWords.payroll;
    }

    String payRuleLabel() {
      switch (p.payRule.type) {
        case PayDateRuleType.nextMonthlyDay:
          return '매달 ${p.payRule.monthlyDay ?? 10}일 지급';
        case PayDateRuleType.samePeriodEndDay:
          return '마감일 지급';
        case PayDateRuleType.afterEndPlusDays:
          return '마감 +${p.payRule.plusDays ?? 0}일 지급';
        case PayDateRuleType.fixedDate:
          return '지정일 지급';
      }
    }

    return '${typeLabel()} · ${payRuleLabel()}';
  }

  void _applyStoreDefaultsToFields(AlbaStoreDefaultsSnapshot d) {
    _wage.text = _commaInt(d.hourlyWage);
    _tax = d.tax;
    _ins = d.insurance;
    _surcharge = d.surcharge;
    _payrollPolicy = d.payrollPolicy;
  }

  String _commaInt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  String _formatMoneyText(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final noLeading = digits.replaceFirst(RegExp(r'^0+'), '');
    if (noLeading.isEmpty) return '';
    final v = int.tryParse(noLeading) ?? 0;
    return _commaInt(v);
  }

  int _parseMoney(String raw) {
    final clean = raw.replaceAll(',', '').trim();
    if (clean.isEmpty) return 0;
    return int.tryParse(clean) ?? 0;
  }

  bool _shouldCheckDate(DateTime dUtc) {
    if (widget.editingAlbaId == null) return true;
    return !_existingDatesOfEditingAlbaUtc.contains(dUtc);
  }

  bool _hasConflictOn(DateTime dLocal) {
    final sMin0 = _startH * 60 + _startM;
    var eMin0 = _endH * 60 + _endM;
    if (eMin0 <= sMin0) eMin0 += 24 * 60;

    bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
      for (final sc in list) {
        var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
        var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60;
        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    List<UICalendarSchedule> byYmd(DateTime x) => widget.existingSchedules
        .where((s) => s.year == x.year && s.month == x.month && s.day == x.day)
        .toList();

    final prev = DateTime(dLocal.year, dLocal.month, dLocal.day - 1);
    final next = DateTime(dLocal.year, dLocal.month, dLocal.day + 1);

    return overlapWith(byYmd(dLocal), 0) ||
        overlapWith(byYmd(prev), -1) ||
        overlapWith(byYmd(next), 1);
  }

  Future<void> _pickDates() async {
    final res = await showDateAssignSheet(
      context,
      existing: _selected,
      checkConflict: (utc) {
        if (!_shouldCheckDate(utc)) return false;
        return _hasConflictOn(DateTime(utc.year, utc.month, utc.day));
      },
    );
    if (!mounted) return;
    if (res != null) setState(() => _selected = res.selectedDates);
  }

  Future<void> _pickTimeCupertino() async {
    final result = await cp.showWorkTimePicker(
      context,
      startHour24: _startH,
      startMinute: _startM,
      endHour24: _endH,
      endMinute: _endM,
    );
    if (result == null || !mounted) return;
    setState(() {
      _startH = result.startHour24;
      _startM = result.startMinute;
      _endH = result.endHour24;
      _endM = result.endMinute;
    });
  }

  Future<void> _pickBreak() async {
    await cp.showBreakSheet(
      context: context,
      initialMinutes: _breakMin,
      onDone: (m) => setState(() => _breakMin = m),
    );
  }

  Future<void> _openPolicy() async {
    if (_lockPolicyFields) return;
    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
      showWeeklyToggles: false, // 주휴·주40시간은 인라인 토글로 관리
    );
    if (!mounted) return;
    if (r != null) {
      setState(() {
        _tax = r.tax;
        _ins = r.ins;
        // ✅ weeklyHoliday + weeklyOver40는 인라인 토글로 관리 - surcharge에서 분리
        final s = r.surcharge;
        _surcharge = s?.copyWith(
          weeklyHolidayEnabled: false,
          // overtimeRule이 weeklyOver40이면 인라인 토글에서 관리하므로 제거
          overtimeEnabled: (s.overtimeRule == pol.OvertimeRule.weeklyOver40)
              ? false
              : s.overtimeEnabled,
          overtimeRule: pol.OvertimeRule.dailyOver8,
        );
      });
    }
  }

  // ✅ 급여정책 편집(알바도 가능)
  Future<void> _openPayrollPolicy() async {
    if (_lockPolicyFields) return;

    final r = await showPayrollPolicySheet(
      context: context,
      initial: _payrollPolicy,
      role: PayrollViewerRole.worker,
    );
    if (!mounted || r == null) return;

    setState(() {
      _payrollPolicy = r;
      _payrollConfirmed = true; // ✅ “설정 완료” 표시
    });
  }

  // ─────────────────────────────────────────
  // 시급 변동 적용 범위 팝업
  // ─────────────────────────────────────────

  /// 시급이 변경됐을 때 적용 범위를 물어보는 팝업
  /// Returns null → 취소, ({effectiveFrom, onlyToday}) → 확인
  Future<({DateTime? effectiveFrom, bool onlyToday})?> _showWageApplyDialog(
    int oldWage,
    int newWage,
  ) async {
    int? selected; // 0=오늘 하루만, 1=오늘부터, 2=날짜 선택
    DateTime? pickedDate;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    String _fmt(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '시급 변경 적용',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  children: [
                    TextSpan(
                        text: '${_comma(oldWage)}원 → ${_comma(newWage)}원\n'),
                    const TextSpan(text: '언제부터 적용할까요?'),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ① 오늘부터 적용
              _AlbaFormWageOptionTile(
                label: '오늘부터 적용',
                sublabel: '${_fmt(todayDate)} 이후 모든 근무에 적용',
                selected: selected == 0,
                onTap: () => ss(() {
                  selected = 0;
                  pickedDate = null;
                }),
              ),
              const SizedBox(height: 8),
              // ② 날짜 선택
              _AlbaFormWageOptionTile(
                label: '날짜 선택',
                sublabel: pickedDate != null
                    ? '${_fmt(pickedDate!)}부터 적용'
                    : '적용할 시작 날짜를 선택하세요',
                selected: selected == 1,
                onTap: () async {
                  final picked = await cp.showSingleDatePickerDialog(
                    ctx,
                    initialDate: today,
                  );
                  if (picked != null) {
                    ss(() {
                      selected = 1;
                      pickedDate =
                          DateTime(picked.year, picked.month, picked.day);
                    });
                  }
                },
                trailing: selected == 1 && pickedDate != null
                    ? const Icon(Icons.event,
                        size: 16, color: Color(0xFF7C3AED))
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('취소', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            TextButton(
              onPressed:
                  selected == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('확인',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return null;

    // 0=오늘부터, 1=날짜선택
    if (selected == 0) {
      return (effectiveFrom: todayDate, onlyToday: false);
    } else {
      return (effectiveFrom: pickedDate, onlyToday: false);
    }
  }

  /// 가산정책 변경 적용 범위 선택 팝업 (시급 팝업과 동일한 UX)
  Future<DateTime?> _showPolicyApplyDialog() async {
    int? selected;
    DateTime? pickedDate;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    String _fmt(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '수당 정책 변경 적용',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              SizedBox(height: 6),
              Text(
                '언제부터 적용할까요?',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlbaFormWageOptionTile(
                label: '오늘부터 적용',
                sublabel: '${_fmt(todayDate)} 이후 모든 근무에 적용',
                selected: selected == 0,
                onTap: () => ss(() {
                  selected = 0;
                  pickedDate = null;
                }),
              ),
              const SizedBox(height: 8),
              _AlbaFormWageOptionTile(
                label: '날짜 선택',
                sublabel: pickedDate != null
                    ? '${_fmt(pickedDate!)}부터 적용'
                    : '적용할 시작 날짜를 선택하세요',
                selected: selected == 1,
                onTap: () async {
                  final picked = await cp.showSingleDatePickerDialog(
                    ctx,
                    initialDate: today,
                  );
                  if (picked != null) {
                    ss(() {
                      selected = 1;
                      pickedDate =
                          DateTime(picked.year, picked.month, picked.day);
                    });
                  }
                },
                trailing: selected == 1 && pickedDate != null
                    ? const Icon(Icons.event,
                        size: 16, color: Color(0xFF7C3AED))
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('취소', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            TextButton(
              onPressed:
                  selected == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('확인',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return null; // null = 취소

    // 0=오늘부터, 1=날짜선택
    if (selected == 0) return todayDate;
    return pickedDate;
  }

  /// 가산정책이 바뀌었는지 비교
  bool _policyChanged(pol.SurchargePolicy? after) {
    final before = _initialSurcharge;
    final beforeWeeklyHoliday = _initialWeeklyHoliday ?? false;
    final beforeWeeklyOvertime = _initialWeeklyOvertime ?? false;
    final afterWeeklyHoliday = _weeklyHoliday;
    final afterWeeklyOvertime = _weeklyOvertime;

    if (beforeWeeklyHoliday != afterWeeklyHoliday) return true;
    if (beforeWeeklyOvertime != afterWeeklyOvertime) return true;
    if ((before?.overtimeEnabled ?? false) != (after?.overtimeEnabled ?? false))
      return true;
    if ((before?.overtimePercent ?? 0) != (after?.overtimePercent ?? 0))
      return true;
    if ((before?.holidayEnabled ?? false) != (after?.holidayEnabled ?? false))
      return true;
    if ((before?.holidayPercent ?? 0) != (after?.holidayPercent ?? 0))
      return true;
    if ((before?.nightEnabled ?? false) != (after?.nightEnabled ?? false))
      return true;
    if ((before?.nightPercent ?? 0) != (after?.nightPercent ?? 0)) return true;
    return false;
  }

  String _comma(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  Future<void> _onSubmit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('매장 이름을 적어주세요.')),
      );
      return;
    }

    // 신규 조인 시 본인 이름 필수
    final isNewJoin = !_isEdit && _storeId.isNotEmpty;
    final workerNameInput = _workerNameCtrl.text.trim();
    if (isNewJoin && workerNameInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('본인 이름을 적어주세요.')),
      );
      return;
    }

    // ✅ 급여정책 미설정이면 저장 막기 (개인 알바 생성/편집 포함)
    // - inherit ON(매장정책 사용)이면 설정된 걸로 취급
    final payrollOk = _lockPolicyFields ? true : _payrollConfirmed;
    if (!payrollOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('급여정책을 먼저 설정해 주세요.')),
      );
      return;
    }

    if (_inheritFromStore && _storeDefaults != null) {
      _applyStoreDefaultsToFields(_storeDefaults!);
      _payrollPolicy = _storeDefaults!.payrollPolicy;
      _payrollConfirmed = true;
    }

    final newWage = _parseMoney(_wage.text);
    if (newWage <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시급을 입력해 주세요.')),
      );
      return;
    }

    final conflicts = <DateTime>[];
    for (final utc in _selected) {
      if (!_shouldCheckDate(utc)) continue;
      final local = DateTime(utc.year, utc.month, utc.day);
      if (_hasConflictOn(local)) conflicts.add(local);
    }
    if (conflicts.isNotEmpty) {
      conflicts.sort((a, b) => a.compareTo(b));
      final msg = conflicts.map(_ymd).join(', ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('시간이 겹쳐요'),
          content: Text('$msg\n이 날짜는 다른 근무와 시간이 겹쳐서 저장할 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('알겠어요'),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ 인라인 토글(주휴수당·주40시간)과 policy sheet 결과를 합산
    // _surcharge: 정책 시트에서 온 값 (dailyOver8 연장, 휴일, 야간만 포함)
    // _weeklyHoliday: 인라인 주휴 토글
    // _weeklyOvertime: 인라인 주 40시간 토글
    var finalSurcharge = (_surcharge ?? const pol.SurchargePolicy()).copyWith(
      weeklyHolidayEnabled: _weeklyHoliday,
    );
    if (_weeklyOvertime) {
      // 주 40시간 연장수당 ON → overtimeRule 교체 (dailyOver8 연장은 비활성)
      finalSurcharge = finalSurcharge.copyWith(
        overtimeEnabled: true,
        overtimeRule: pol.OvertimeRule.weeklyOver40,
        overtimePercent: finalSurcharge.overtimePercent > 0
            ? finalSurcharge.overtimePercent
            : 50,
      );
    }
    // 아무것도 켜지지 않으면 null 처리
    final anyOn = finalSurcharge.weeklyHolidayEnabled ||
        finalSurcharge.overtimeEnabled ||
        finalSurcharge.holidayEnabled ||
        finalSurcharge.nightEnabled;
    final effectiveSurcharge = anyOn ? finalSurcharge : null;

    // ✅ 수정 모드에서 시급 변동 시 적용 범위 팝업
    DateTime? wageEffectiveFrom;
    bool wageOnlyToday = false;

    if (_isEdit && _initialWage != null && newWage != _initialWage) {
      final result = await _showWageApplyDialog(_initialWage!, newWage);
      if (result == null) return; // 취소
      wageEffectiveFrom = result.effectiveFrom;
      wageOnlyToday = result.onlyToday;
    }

    // ✅ 수정 모드에서 가산정책 변동 시 적용 범위 팝업
    DateTime? policyEffectiveFrom;

    if (_isEdit && _policyChanged(effectiveSurcharge)) {
      final picked = await _showPolicyApplyDialog();
      if (picked == null) return; // 취소
      policyEffectiveFrom = picked;
    }

    final isNewJoinFinal = !_isEdit && _storeId.isNotEmpty;
    widget.onSubmit(
      AlbaFormResult(
        storeId: _storeId,
        inheritFromStore: _inheritFromStore,
        workerName: isNewJoinFinal ? _workerNameCtrl.text.trim() : null,
        storeName: name,
        hourlyWage: newWage,
        colorHex: _colorHex,
        tax: _tax,
        ins: _ins,
        surcharge: effectiveSurcharge,
        payrollPolicy: _payrollPolicy,
        startHour24: _startH,
        startMinute: _startM,
        endHour24: _endH,
        endMinute: _endM,
        breakMinutes: _breakMin,
        selectedDates: _selected,
        payDay: _deriveLegacyPayDay(_payrollPolicy),
        wageEffectiveFrom: wageEffectiveFrom,
        wageOnlyToday: wageOnlyToday,
        policyEffectiveFrom: policyEffectiveFrom,
      ),
    );
  }

  int _deriveLegacyPayDay(PayrollPolicy p) {
    // ✅ 급여일 규칙에서 실제 지급일을 추출
    if (p.payRule.type == PayDateRuleType.nextMonthlyDay) {
      return (p.payRule.monthlyDay ?? 25).clamp(1, 31);
    }
    if (p.cycle == PayCycleType.monthly) {
      return (p.monthlyStartDay ?? 1).clamp(1, 31);
    }
    return 25;
  }

  @override
  Widget build(BuildContext context) {
    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: const Color(0xFF111827)),
          onPressed: widget.onBack,
        ),
        title: Text(
          _isEdit ? '알바 수정' : '알바 등록',
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF111827)),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _onSubmit,
            child: const Text('저장',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF7C3AED))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          // ── 매장 소속 알바 안내 배너 (신규 조인 + 수정 모두)
          if (_storeId.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.store_outlined,
                      size: 16, color: Color(0xFF7C3AED)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '시급·세금·정책은 사장님이 관리해요.',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF6D28D9), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ─────────────────────────────────────
          // 0) 신규 조인: 본인 이름 + 매장 별칭
          // ─────────────────────────────────────
          if (!_isEdit && _storeId.isNotEmpty) ...[
            // 본인 이름 카드
            _FormCard(
              label: '내 이름',
              child: TextField(
                controller: _workerNameCtrl,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '사장님이 보는 내 이름',
                  hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ─────────────────────────────────────
          // 1) HERO: 색상 + 매장 이름(별칭)
          // ─────────────────────────────────────
          _FormCard(
            child: Row(
              children: [
                // 색상 도트 (탭 → 팔레트)
                GestureDetector(
                  onTap: () => setState(() => _showPalette = true),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _color.withOpacity(0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.palette_outlined,
                        color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 14),
                // 이름 입력
                Expanded(
                  child: TextField(
                    controller: _name,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827)),
                    decoration: InputDecoration(
                      hintText: _storeId.isNotEmpty
                          ? '내가 부르는 매장 이름 (예: 스타벅스)'
                          : '예: 스타벅스 강남점',
                      hintStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFD1D5DB)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _color, width: 2),
                      ),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────
          // 2) 시급 HERO - 매장 소속 알바는 숨김 (사장님 관리)
          // ─────────────────────────────────────
          if (_storeId.isEmpty) ...[
            _FormCard(
              label: '시급',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wage,
                      focusNode: _wageFocus,
                      enabled: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _lockStoreFields
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF111827),
                        letterSpacing: -0.5,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE5E7EB)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('원',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _lockStoreFields
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF374151))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ─────────────────────────────────────
          // 3) 근무 시간 + 쉬는 시간
          // ─────────────────────────────────────
          _FormCard(
            label: '근무 시간',
            child: Column(
              children: [
                _TapRow(
                  icon: Icons.access_time_rounded,
                  label: '시간',
                  value:
                      '${_fmtAmPm(_startH, _startM)} ~ ${_fmtAmPm(_endH, _endM)}'
                      '${((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? "  다음날" : ""}',
                  accent: _color,
                  onTap: _pickTimeCupertino,
                ),
                const SizedBox(height: 8),
                _TapRow(
                  icon: Icons.coffee_outlined,
                  label: '쉬는 시간',
                  value: _breakMin == 0 ? '없음' : '$_breakMin분',
                  accent: _color,
                  onTap: _pickBreak,
                ),
                const SizedBox(height: 8),
                // ✅ 주휴수당/연장수당 토글 - 매장 소속 알바는 숨김
                if (_storeId.isEmpty) ...[
                  _WeeklyHolidayRow(
                    value: _weeklyHoliday,
                    accent: _color,
                    onChanged: (v) => setState(() => _weeklyHoliday = v),
                  ),
                  const SizedBox(height: 8),
                  _WeeklyOvertimeRow(
                    value: _weeklyOvertime,
                    accent: _color,
                    onChanged: (v) => setState(() => _weeklyOvertime = v),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────
          // 4) 근무 날짜
          // ─────────────────────────────────────
          GestureDetector(
            onTap: _pickDates,
            child: _FormCard(
              label: '근무 날짜',
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _selected.isEmpty ? '날짜 선택' : '${_selected.length}일 선택됨',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
              child: _selected.isEmpty
                  ? Row(
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 18, color: const Color(0xFFD1D5DB)),
                        const SizedBox(width: 8),
                        const Text('날짜를 선택해 주세요',
                            style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFFD1D5DB),
                                fontWeight: FontWeight.w500)),
                      ],
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d
                            in (_selected.toList()
                              ..sort((a, b) => a.compareTo(b))))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _ymd(d),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _color),
                            ),
                          ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────
          // 5) 급여 정책 (별도 카드)
          // ─────────────────────────────────────
          GestureDetector(
            onTap: _lockPolicyFields ? null : _openPayrollPolicy,
            child: _FormCard(
              label: '급여 정책',
              trailing: (!_lockPolicyFields && !_payrollConfirmed)
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('설정 필요',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 18,
                      color: (!_lockPolicyFields && !_payrollConfirmed)
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _payrollSummaryLine(_payrollPolicy),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _lockPolicyFields
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF374151),
                      ),
                    ),
                  ),
                  if (!_lockPolicyFields)
                    const Icon(Icons.chevron_right,
                        size: 18, color: Color(0xFF9CA3AF)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────
          // 6) 접이식: 세금·보험·가산
          // ─────────────────────────────────────
          _ExpandableCard(
            label: '세금·보험·가산',
            badge: null, // ✅ 선택사항 - 배지 불필요
            accentColor: _color,
            children: [
              // 세금
              _SettingRow(
                icon: Icons.receipt_long_outlined,
                label: '세금',
                value: _labelTax(_tax),
                locked: _lockPolicyFields,
                onTap: _lockPolicyFields ? null : _openPolicy,
              ),
              const SizedBox(height: 2),
              // 보험
              _SettingRow(
                icon: Icons.health_and_safety_outlined,
                label: '보험',
                value: _labelIns(_ins),
                locked: _lockPolicyFields,
                onTap: _lockPolicyFields ? null : _openPolicy,
              ),
              const SizedBox(height: 2),
              // 야간·연장·휴일
              _SettingRow(
                icon: Icons.nightlight_outlined,
                label: '야간·연장·휴일',
                value:
                    _surcharge == null ? '없음' : _summarySurcharge(_surcharge!),
                locked: _lockPolicyFields,
                onTap: _lockPolicyFields ? null : _openPolicy,
              ),
            ],
          ),
        ],
      ),
    ).withColorPaletteDialog(
      show: _showPalette,
      initialHex: _colorHex,
      onPick: (hex) => setState(() {
        _colorHex = hex;
        _showPalette = false;
      }),
      onDismiss: () => setState(() => _showPalette = false),
    );
  }

  String _labelTax(pol.TaxConfig t) {
    if (t == pol.TaxConfig.none) return AppWords.none;
    if (t == pol.TaxConfig.biz33) return '3.3%';
    if (t == pol.TaxConfig.day66) return '6.6%';
    if (t is pol.TaxConfigCustomPercent) return '직접 입력 ${trimPct(t.percent)}%';
    return AppWords.tax;
  }

  String _labelIns(pol.InsuranceConfig i) {
    if (i is pol.InsuranceNone) return AppWords.none;
    if (i is pol.InsuranceEmploymentOnly) return '고용보험';
    if (i is pol.InsuranceFour) return '4대보험';
    return AppWords.insurance;
  }

  String _summarySurcharge(pol.SurchargePolicy s) {
    final list = <String>[];
    // ✅ 주휴는 근무시간 카드에서 별도 표시하므로 여기선 제외
    if (s.overtimeEnabled) list.add('연장 +${trimPct(s.overtimePercent)}%');
    if (s.holidayEnabled) list.add('휴일 +${trimPct(s.holidayPercent)}%');
    if (s.nightEnabled) list.add('야간 +${trimPct(s.nightPercent)}%');
    return list.isEmpty ? AppWords.none : list.join(', ');
  }
}

/* ═══════════════════════════════════════════════
   🎨 Paymoa 알바폼 UI 컴포넌트
   ═══════════════════════════════════════════════ */

// ── 기본 카드 컨테이너
class _FormCard extends StatelessWidget {
  const _FormCard({required this.child, this.label, this.trailing});
  final Widget child;
  final String? label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEBE6), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.03),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                Text(label!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.5)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ] else if (trailing != null) ...[
            Align(alignment: Alignment.centerRight, child: trailing!),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

// ── 탭 가능한 설정 행 (근무시간/쉬는시간)
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: accent.withOpacity(0.7))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: accent.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}

// ── 접이식 설정 카드
class _ExpandableCard extends StatefulWidget {
  const _ExpandableCard({
    required this.label,
    required this.children,
    required this.accentColor,
    this.badge,
  });
  final String label;
  final List<Widget> children;
  final Color accentColor;
  final String? badge;

  @override
  State<_ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<_ExpandableCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더 행
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Text(widget.label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151))),
                  const SizedBox(width: 8),
                  if (widget.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(widget.badge!,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444))),
                    ),
                  const Spacer(),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: widget.accentColor,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          // 펼쳐지는 내용
          if (_open) ...[
            Container(height: 1, color: const Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(children: widget.children),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 설정 내부 행 (급여/세금/보험/야간)
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.hasAlert = false,
    this.locked = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool hasAlert;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: hasAlert
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF9CA3AF)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hasAlert
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6B7280))),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hasAlert
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF111827))),
            const SizedBox(width: 4),
            if (!locked)
              const Icon(Icons.chevron_right,
                  size: 16, color: Color(0xFFD1D5DB)),
            if (locked)
              const Icon(Icons.lock_outline,
                  size: 14, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }
}

// ── 주휴수당 토글 행 (근무시간 카드 내부)
class _WeeklyHolidayRow extends StatelessWidget {
  const _WeeklyHolidayRow({
    required this.value,
    required this.accent,
    required this.onChanged,
  });
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value ? accent.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: value ? accent : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '주휴수당',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: value ? accent : const Color(0xFF374151),
                  ),
                ),
                Text(
                  '주 15시간 이상 근무 시 1일치 급여 추가',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: value
                        ? accent.withOpacity(0.7)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ── 주 40시간 초과 연장수당 토글 행
class _WeeklyOvertimeRow extends StatelessWidget {
  const _WeeklyOvertimeRow({
    required this.value,
    required this.accent,
    required this.onChanged,
  });
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value ? accent.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 16,
            color: value ? accent : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '주 40시간 초과 연장수당',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: value ? accent : const Color(0xFF374151),
                  ),
                ),
                Text(
                  '한 주 40시간 넘으면 초과분 50% 추가',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: value
                        ? accent.withOpacity(0.7)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

String trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

extension _PaletteDialogExt on Widget {
  Widget withColorPaletteDialog({
    required bool show,
    required String initialHex,
    required ValueChanged<String> onPick,
    required VoidCallback onDismiss,
  }) {
    if (!show) return this;
    return Stack(
      children: [
        this,
        _ColorPaletteDialog(
          initialHex: initialHex,
          onPick: onPick,
          onDismiss: onDismiss,
        ),
      ],
    );
  }
}

class _ColorPaletteDialog extends StatelessWidget {
  const _ColorPaletteDialog({
    required this.initialHex,
    required this.onPick,
    required this.onDismiss,
  });

  final String initialHex;
  final ValueChanged<String> onPick;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = <String>[
      '#EF4444',
      '#F97316',
      '#F59E0B',
      '#EAB308',
      '#84CC16',
      '#22C55E',
      '#10B981',
      '#06B6D4',
      '#3B82F6',
      '#8B5CF6',
      '#EC4899',
      '#7C3AED',
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('색상 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: colors.map((hex) {
                final selected = hex.toUpperCase() == initialHex.toUpperCase();
                final c = cp.parseColor(hex);
                return GestureDetector(
                  onTap: () => onPick(hex.toUpperCase()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: c.withOpacity(selected ? 0.6 : 0.25),
                          blurRadius: selected ? 10 : 4,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                ),
                child: const Text('닫기',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ───────────────────────── 시급 적용 옵션 타일 ───────────────────────── */

class _AlbaFormWageOptionTile extends StatelessWidget {
  const _AlbaFormWageOptionTile({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF7C3AED);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? primary.withOpacity(0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected ? primary.withOpacity(0.4) : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? primary : const Color(0xFFD1D5DB),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? primary : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? primary.withOpacity(0.7)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
