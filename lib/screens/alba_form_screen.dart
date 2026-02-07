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
  final _name = TextEditingController();

  final _wage = TextEditingController(text: '');
  final _wageFocus = FocusNode();
  bool _formattingWage = false;

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

      _tax = i.tax;
      _ins = i.insurance;
      _surcharge = i.surcharge;

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
    _wage.dispose();
    _wageFocus.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.editingAlbaId != null;

  Color get _color => cp.parseColor(_colorHex);
  String _fmtAmPm(int h, int m) => cp.fmtAmPm(h, m);

  String _ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _fmtYmdLocal(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  bool get _canShowInheritToggle =>
      _storeId.isNotEmpty && _storeDefaults != null;

  bool get _lockStoreFields => _canShowInheritToggle && _inheritFromStore;

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
    int sAmpm = _startH < 12 ? 0 : 1;
    int sHour = (_startH % 12 == 0) ? 12 : _startH % 12;
    int sMin = _startM;

    int eAmpm = _endH < 12 ? 0 : 1;
    int eHour = (_endH % 12 == 0) ? 12 : _endH % 12;
    int eMin = _endM;

    int to24(int ampmIdx, int h12) {
      if (h12 == 12) h12 = 0;
      return ampmIdx == 0 ? h12 : h12 + 12;
    }

    final ampm = const ['오전', '오후'];
    final hours = List<int>.generate(12, (i) => i + 1);
    final minutes = List<int>.generate(60, (i) => i);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(AppWords.close),
                    ),
                    const Spacer(),
                    const Text(AppWords.workTime),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _startH = to24(sAmpm, sHour);
                          _startM = sMin;
                          _endH = to24(eAmpm, eHour);
                          _endM = eMin;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text(AppWords.select),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text('시작', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: sAmpm,
                                      ),
                                      onSelectedItemChanged: (i) => sAmpm = i,
                                      children: ampm
                                          .map((t) => Center(child: Text(t)))
                                          .toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: hours.indexOf(sHour),
                                      ),
                                      onSelectedItemChanged: (i) =>
                                          sHour = hours[i],
                                      children: hours
                                          .map((h) => Center(child: Text('$h')))
                                          .toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: sMin,
                                      ),
                                      onSelectedItemChanged: (i) => sMin = i,
                                      children: minutes
                                          .map((m) => Center(
                                                child: Text(
                                                  m.toString().padLeft(2, '0'),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            Text('종료', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: eAmpm,
                                      ),
                                      onSelectedItemChanged: (i) => eAmpm = i,
                                      children: ampm
                                          .map((t) => Center(child: Text(t)))
                                          .toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: hours.indexOf(eHour),
                                      ),
                                      onSelectedItemChanged: (i) =>
                                          eHour = hours[i],
                                      children: hours
                                          .map((h) => Center(child: Text('$h')))
                                          .toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: eMin,
                                      ),
                                      onSelectedItemChanged: (i) => eMin = i,
                                      children: minutes
                                          .map((m) => Center(
                                                child: Text(
                                                  m.toString().padLeft(2, '0'),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_fmtAmPm(to24(sAmpm, sHour), sMin)} ~ ${_fmtAmPm(to24(eAmpm, eHour), eMin)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickBreak() async {
    await cp.showBreakSheet(
      context: context,
      initialMinutes: _breakMin,
      onDone: (m) => setState(() => _breakMin = m),
    );
  }

  Future<void> _openPolicy() async {
    if (_lockStoreFields) return;
    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
    );
    if (!mounted) return;
    if (r != null) {
      setState(() {
        _tax = r.tax;
        _ins = r.ins;
        _surcharge = r.surcharge;
      });
    }
  }

  // ✅ 급여정책 편집(알바도 가능)
  Future<void> _openPayrollPolicy() async {
    if (_lockStoreFields) return;

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

  Future<void> _onSubmit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름을 적어주세요.')),
      );
      return;
    }

    // ✅ 급여정책 미설정이면 저장 막기 (개인 알바 생성/편집 포함)
    // - inherit ON(매장정책 사용)이면 설정된 걸로 취급
    final payrollOk = _lockStoreFields ? true : _payrollConfirmed;
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
    if (newWage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시급을 확인해 주세요.')),
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

    widget.onSubmit(
      AlbaFormResult(
        storeId: _storeId,
        inheritFromStore: _inheritFromStore,
        storeName: name,
        hourlyWage: newWage,
        colorHex: _colorHex,
        tax: _tax,
        ins: _ins,
        surcharge: _surcharge,
        payrollPolicy: _payrollPolicy,
        startHour24: _startH,
        startMinute: _startM,
        endHour24: _endH,
        endMinute: _endM,
        breakMinutes: _breakMin,
        selectedDates: _selected,
        payDay: _deriveLegacyPayDay(_payrollPolicy),
        wageEffectiveFrom: null,
      ),
    );
  }

  int _deriveLegacyPayDay(PayrollPolicy p) {
    if (p.cycle == PayCycleType.monthly) {
      return (p.monthlyStartDay ?? 1).clamp(1, 31);
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: widget.onBack,
          child: const Text(AppWords.back),
        ),
        title: Text(_isEdit ? '근무 수정' : '근무 등록'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _onSubmit,
            child: const Text(AppWords.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_canShowInheritToggle)
            _Card(
              title: AppWords.inheritStoreSetting,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _inheritFromStore,
                    onChanged: (v) {
                      setState(() {
                        _inheritFromStore = v;

                        if (_inheritFromStore && _storeDefaults != null) {
                          _applyStoreDefaultsToFields(_storeDefaults!);
                          _payrollPolicy = _storeDefaults!.payrollPolicy;
                          _payrollConfirmed = true;
                        }
                      });
                    },
                    title: const Text('매장 설정 그대로'),
                    subtitle: Text(
                      _inheritFromStore
                          ? '켜면 매장 설정을 그대로 써요.'
                          : '끄면 이 설정만 따로 써요.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                  if (_inheritFromStore && _storeDefaults != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '가능하면 켜는 걸 추천해요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_canShowInheritToggle) const SizedBox(height: 12),

          _Card(
            title: '기본 설정',
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: AppWords.name,
                    hintText: AppWords.storeAliasHint,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _wage,
                  focusNode: _wageFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !_lockStoreFields,
                  decoration: InputDecoration(
                    labelText: '시급',
                    hintText: '예: 10030',
                    helperText: _lockStoreFields ? '매장 시급 사용 중' : null,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showPalette = true),
                  child: Row(
                    children: [
                      Text('색상', style: theme.textTheme.labelLarge),
                      const Spacer(),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _color,
                          border: Border.all(color: theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _Card(
            title: '공제/수당',
            trailing: TextButton(
              onPressed: _lockStoreFields ? null : _openPolicy,
              child: Text(_lockStoreFields ? '매장 설정' : '바꾸기'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${AppWords.tax}: ${_labelTax(_tax)}'),
                Text('${AppWords.insurance}: ${_labelIns(_ins)}'),
                Text(
                  '${AppWords.surcharge}: ${_surcharge == null ? AppWords.none : _summarySurcharge(_surcharge!)}',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ✅ 급여정책: 알바도 편집 가능 + “미설정이면 저장 불가”
          _Card(
            title: AppWords.payroll,
            trailing: TextButton(
              onPressed: _lockStoreFields ? null : _openPayrollPolicy,
              child: Text(_lockStoreFields
                  ? '매장 설정'
                  : (_payrollConfirmed ? AppWords.change : '설정하기')),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _payrollSummaryLine(_payrollPolicy),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!_lockStoreFields && !_payrollConfirmed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '필수',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '예시: ${_fmtYmdLocal(preview.period.start)} ~ ${_fmtYmdLocal(preview.period.end)} / 지급일 ${_fmtYmdLocal(preview.payDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _lockStoreFields
                      ? '지금은 매장 설정을 그대로 사용 중이에요.'
                      : (_payrollConfirmed
                          ? '이 알바의 급여정책이 설정되어 있어요.'
                          : '저장하려면 급여정책을 먼저 설정해 주세요.'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _Card(
            title: '근무 시간/날짜',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: AppWords.workTime,
                  value:
                      '${_fmtAmPm(_startH, _startM)} ~ ${_fmtAmPm(_endH, _endM)}'
                      '${((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? " (다음날)" : ""}',
                  action: TextButton(
                    onPressed: _pickTimeCupertino,
                    child: const Text('바꾸기'),
                  ),
                ),
                const SizedBox(height: 8),
                _Line(
                  label: AppWords.breakTime,
                  value: '${_breakMin}분',
                  action: TextButton(
                    onPressed: _pickBreak,
                    child: const Text('바꾸기'),
                  ),
                ),
                const SizedBox(height: 8),
                _Line(
                  label: AppWords.workDate,
                  value: _selected.isEmpty
                      ? AppWords.none
                      : (_selected.length == 1
                          ? _ymd(_selected.first)
                          : '${_selected.length}일'),
                  action: TextButton(
                    onPressed: _pickDates,
                    child: const Text('고르기'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
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
    if (s.weeklyHolidayEnabled) list.add('주휴');
    if (s.overtimeEnabled) list.add('연장 +${trimPct(s.overtimePercent)}%');
    if (s.holidayEnabled) list.add('휴일 +${trimPct(s.holidayPercent)}%');
    if (s.nightEnabled) list.add('야간 +${trimPct(s.nightPercent)}%');
    return list.isEmpty ? AppWords.none : list.join(', ');
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.trailing, required this.child});
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.action});
  final String label;
  final String value;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('$label: $value')),
        action,
      ],
    );
  }
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
    ];

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('색 고르기', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((hex) {
                final selected = hex.toUpperCase() == initialHex.toUpperCase();
                return InkWell(
                  onTap: () => onPick(hex.toUpperCase()),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cp.parseColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDismiss,
                child: const Text(AppWords.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
