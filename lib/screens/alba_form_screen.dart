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
import 'payroll_policy_sheet.dart';

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

  final _nameFocus = FocusNode();
  final _workerNameFocus = FocusNode();

  final _wage = TextEditingController(text: '');
  final _wageFocus = FocusNode();
  bool _formattingWage = false;

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

  bool _weeklyHoliday = false;
  bool _weeklyOvertime = false;

  pol.SurchargePolicy? _initialSurcharge;
  bool? _initialWeeklyHoliday;
  bool? _initialWeeklyOvertime;

  late PayrollPolicy _payrollPolicy;

  bool _payrollConfirmed = false;

  String _storeId = '';
  bool _inheritFromStore = true;
  AlbaStoreDefaultsSnapshot? _storeDefaults;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _payrollPolicy = PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(10),
    );
    _payrollConfirmed = false;

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
      _name.text = i.storeName;
      _wage.text = _commaInt(i.hourlyWage);
      _colorHex = i.colorHex;

      if (widget.editingAlbaId != null) {
        _initialWage = i.hourlyWage;
      }

      _tax = i.tax;
      _ins = i.insurance;
      _surcharge = i.surcharge;
      _weeklyHoliday = i.surcharge?.weeklyHolidayEnabled ?? false;
      _weeklyOvertime = (i.surcharge?.overtimeEnabled ?? false) &&
          (i.surcharge?.overtimeRule == pol.OvertimeRule.weeklyOver40);

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

      if (sd != null) {
        _payrollPolicy = sd.payrollPolicy;
        _payrollConfirmed = true;
      } else if (i.payrollPolicy != null) {
        _payrollPolicy = i.payrollPolicy!;
        _payrollConfirmed = true;
      } else {
        _payrollConfirmed = false;
      }
    }

    if (widget.editingAlbaId != null) {
      _existingDatesOfEditingAlbaUtc = widget.existingSchedules
          .where((s) => s.albaId == widget.editingAlbaId)
          .map((s) => DateTime.utc(s.year, s.month, s.day))
          .toSet();
    }

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
    _nameFocus.dispose();
    _workerNameFocus.dispose();
    _wage.dispose();
    _wageFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _isEdit => widget.editingAlbaId != null;

  bool get _isJoinEdit => _isEdit && _storeId.isNotEmpty;

  Color get _color => cp.parseColor(_colorHex);
  String _fmtAmPm(int h, int m) => cp.fmtAmPm(h, m);

  String _ymd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _fmtYmdLocal(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  bool get _canShowInheritToggle =>
      _storeId.isNotEmpty && _storeDefaults != null;

  bool get _lockStoreFields =>
      (_canShowInheritToggle && _inheritFromStore) || _isJoinEdit;

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
      if (p.cycle == PayCycleType.customDays) {
        return '${p.customEveryDays ?? 0}일';
      }
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
        .where((s) =>
            s.year == x.year &&
            s.month == x.month &&
            s.day == x.day &&
            s.albaId != widget.editingAlbaId)
        .toList();

    final prev = DateTime(dLocal.year, dLocal.month, dLocal.day - 1);
    final next = DateTime(dLocal.year, dLocal.month, dLocal.day + 1);

    return overlapWith(byYmd(dLocal), 0) ||
        overlapWith(byYmd(prev), -1) ||
        overlapWith(byYmd(next), 1);
  }

  Future<void> _pickDates() async {
    _dismissKeyboard();

    final res = await showDateAssignSheet(
      context,
      existing: _selected,
      checkConflict: (utc) =>
          _hasConflictOn(DateTime(utc.year, utc.month, utc.day)),
    );
    if (!mounted) return;
    if (res != null) {
      setState(() => _selected = res.selectedDates);
    }
  }

  Future<void> _pickTimeCupertino() async {
    _dismissKeyboard();

    final result = await cp.showWorkTimePicker(
      context,
      startHour24: _startH,
      startMinute: _startM,
      endHour24: _endH,
      endMinute: _endM,
    );
    if (!mounted || result == null) return;

    setState(() {
      _startH = result.startHour24;
      _startM = result.startMinute;
      _endH = result.endHour24;
      _endM = result.endMinute;
    });
  }

  Future<void> _pickBreak() async {
    _dismissKeyboard();

    await cp.showBreakSheet(
      context: context,
      initialMinutes: _breakMin,
      onDone: (m) => setState(() => _breakMin = m),
    );
  }

  Future<void> _openPolicy() async {
    if (_lockPolicyFields) return;

    _dismissKeyboard();

    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
      showWeeklyToggles: false,
    );
    if (!mounted) return;

    if (r != null) {
      setState(() {
        _tax = r.tax;
        _ins = r.ins;
        final s = r.surcharge;
        _surcharge = s?.copyWith(
          weeklyHolidayEnabled: false,
          overtimeEnabled: (s.overtimeRule == pol.OvertimeRule.weeklyOver40)
              ? false
              : s.overtimeEnabled,
          overtimeRule: pol.OvertimeRule.dailyOver8,
        );
      });
    }
  }

  Future<void> _openPayrollPolicy() async {
    if (_lockPolicyFields) return;

    _dismissKeyboard();

    final r = await showPayrollPolicySheet(
      context: context,
      initial: _payrollPolicy,
      role: PayrollViewerRole.worker,
    );
    if (!mounted || r == null) return;

    setState(() {
      _payrollPolicy = r;
      _payrollConfirmed = true;
    });
  }

  bool _policyChanged(pol.SurchargePolicy? after) {
    final before = _initialSurcharge;
    final beforeWeeklyHoliday = _initialWeeklyHoliday ?? false;
    final beforeWeeklyOvertime = _initialWeeklyOvertime ?? false;
    final afterWeeklyHoliday = _weeklyHoliday;
    final afterWeeklyOvertime = _weeklyOvertime;

    if (beforeWeeklyHoliday != afterWeeklyHoliday) return true;
    if (beforeWeeklyOvertime != afterWeeklyOvertime) return true;
    if ((before?.overtimeEnabled ?? false) !=
        (after?.overtimeEnabled ?? false)) {
      return true;
    }
    if ((before?.overtimePercent ?? 0) != (after?.overtimePercent ?? 0)) {
      return true;
    }
    if ((before?.holidayEnabled ?? false) != (after?.holidayEnabled ?? false)) {
      return true;
    }
    if ((before?.holidayPercent ?? 0) != (after?.holidayPercent ?? 0)) {
      return true;
    }
    if ((before?.nightEnabled ?? false) != (after?.nightEnabled ?? false)) {
      return true;
    }
    if ((before?.nightPercent ?? 0) != (after?.nightPercent ?? 0)) {
      return true;
    }
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

  DateTime _nextSunday(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final daysUntilSunday = (7 - date.weekday) % 7;
    return date.add(Duration(days: daysUntilSunday == 0 ? 7 : daysUntilSunday));
  }

  Future<void> _onSubmit() async {
    _dismissKeyboard();

    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('매장 이름을 적어주세요.')),
      );
      return;
    }

    final isNewJoin = !_isEdit && _storeId.isNotEmpty;
    final workerNameInput = _workerNameCtrl.text.trim();
    if (isNewJoin && workerNameInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('본인 이름을 적어주세요.')),
      );
      return;
    }

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
      if (!mounted) return;
      return;
    }

    var finalSurcharge = (_surcharge ?? const pol.SurchargePolicy()).copyWith(
      weeklyHolidayEnabled: _weeklyHoliday,
    );
    if (_weeklyOvertime) {
      finalSurcharge = finalSurcharge.copyWith(
        overtimeEnabled: true,
        overtimeRule: pol.OvertimeRule.weeklyOver40,
        overtimePercent: finalSurcharge.overtimePercent > 0
            ? finalSurcharge.overtimePercent
            : 50,
      );
    }

    final anyOn = finalSurcharge.weeklyHolidayEnabled ||
        finalSurcharge.overtimeEnabled ||
        finalSurcharge.holidayEnabled ||
        finalSurcharge.nightEnabled;
    final effectiveSurcharge = anyOn ? finalSurcharge : null;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final nextSunday = _nextSunday(todayDate);

    final bool wageChanged =
        _isEdit && _initialWage != null && newWage != _initialWage;
    final bool policyChanged = _isEdit && _policyChanged(effectiveSurcharge);

    if (wageChanged || policyChanged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            '적용 시작일 안내',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: Text(
            '시급 변경은 오늘(${_fmtYmdLocal(todayDate)})부터 적용됩니다.\n'
            '세금·보험·가산정책 변경은 다음 주 시작일(${_fmtYmdLocal(nextSunday)})부터 적용됩니다.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                '취소',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '확인',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) return;
    }

    final DateTime? wageEffectiveFrom = wageChanged ? todayDate : null;
    final DateTime? policyEffectiveFrom = policyChanged ? nextSunday : null;

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
        wageOnlyToday: false,
        policyEffectiveFrom: policyEffectiveFrom,
      ),
    );
  }

  int _deriveLegacyPayDay(PayrollPolicy p) {
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
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: Color(0xFF111827),
          ),
          onPressed: () {
            _dismissKeyboard();
            widget.onBack();
          },
        ),
        title: Text(
          _isEdit ? '알바 수정' : '알바 등록',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _onSubmit,
            child: const Text(
              '저장',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF7C3AED),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            if (_storeId.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          fontSize: 13,
                          color: Color(0xFF6D28D9),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!_isEdit && _storeId.isNotEmpty) ...[
              _FormCard(
                label: '내 이름',
                child: TextField(
                  controller: _workerNameCtrl,
                  focusNode: _workerNameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_nameFocus);
                  },
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                  decoration: const InputDecoration(
                    hintText: '사장님이 보는 내 이름',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFD1D5DB),
                    ),
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
            _FormCard(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      _dismissKeyboard();
                      final picked = await cp.showColorPaletteDialog(
                        context: context,
                        initialHex: _colorHex,
                      );
                      if (!mounted) return;
                      if (picked != null) {
                        setState(() => _colorHex = picked);
                      }
                    },
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
                      child: const Icon(
                        Icons.palette_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      textInputAction: _storeId.isEmpty
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: (_) {
                        if (_storeId.isEmpty) {
                          FocusScope.of(context).requestFocus(_wageFocus);
                        } else {
                          _dismissKeyboard();
                        }
                      },
                      keyboardType: TextInputType.text,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                      decoration: InputDecoration(
                        hintText: _storeId.isNotEmpty
                            ? '내가 부르는 매장 이름 (예: 스타벅스)'
                            : '예: 스타벅스 강남점',
                        hintStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFD1D5DB),
                        ),
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
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _dismissKeyboard(),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: _lockStoreFields
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF111827),
                          letterSpacing: -0.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE5E7EB),
                          ),
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
                    Text(
                      '원',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _lockStoreFields
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                      color: Colors.white,
                    ),
                  ),
                ),
                child: _selected.isEmpty
                    ? Row(
                        children: const [
                          Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: Color(0xFFD1D5DB),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '날짜를 선택해 주세요',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFFD1D5DB),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _ymd(d),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _color,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _lockPolicyFields ? null : _openPayrollPolicy,
              child: _FormCard(
                label: '급여 정책',
                trailing: (!_lockPolicyFields && !_payrollConfirmed)
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '설정 필요',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 18,
                      color: (!_lockPolicyFields && !_payrollConfirmed)
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF7C3AED),
                    ),
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
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0xFF9CA3AF),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ExpandableCard(
              label: '세금·보험·가산',
              badge: null,
              accentColor: _color,
              children: [
                _SettingRow(
                  icon: Icons.receipt_long_outlined,
                  label: '세금',
                  value: _labelTax(_tax),
                  locked: _lockPolicyFields,
                  onTap: _lockPolicyFields ? null : _openPolicy,
                ),
                const SizedBox(height: 2),
                _SettingRow(
                  icon: Icons.health_and_safety_outlined,
                  label: '보험',
                  value: _labelIns(_ins),
                  locked: _lockPolicyFields,
                  onTap: _lockPolicyFields ? null : _openPolicy,
                ),
                const SizedBox(height: 2),
                _SettingRow(
                  icon: Icons.nightlight_outlined,
                  label: '야간·연장·휴일',
                  value: _surcharge == null
                      ? '없음'
                      : _summarySurcharge(_surcharge!),
                  locked: _lockPolicyFields,
                  onTap: _lockPolicyFields ? null : _openPolicy,
                ),
              ],
            ),
          ],
        ),
      ),
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
    if (s.overtimeEnabled) list.add('연장 +${trimPct(s.overtimePercent)}%');
    if (s.holidayEnabled) list.add('휴일 +${trimPct(s.holidayPercent)}%');
    if (s.nightEnabled) list.add('야간 +${trimPct(s.nightPercent)}%');
    return list.isEmpty ? AppWords.none : list.join(', ');
  }
}

/* ═══════════════════════════════════════════════
   🎨 Paymoa 알바폼 UI 컴포넌트
   ═══════════════════════════════════════════════ */

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
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.5,
                  ),
                ),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: accent.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: accent.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}

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
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.badge!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
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
            Icon(
              icon,
              size: 16,
              color:
                  hasAlert ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: hasAlert
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hasAlert
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF111827),
                ),
              ),
            ),
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
