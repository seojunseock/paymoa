// lib/screens/alba_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; // ← for FilteringTextInputFormatter

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart' as pol;
import '../common/common_pickers.dart' as cp;
import 'date_assign_sheet.dart';

/// 폼 진입 모드:
/// - [initial] 이 있으면 "알바 수정"
/// - 없으면 "알바 등록"
class AlbaFormScreen extends StatefulWidget {
  const AlbaFormScreen({
    super.key,
    required this.existingSchedules, // 선택 날짜 충돌 점검용
    this.initial,                    // 있으면 수정 모드
    this.editingAlbaId,              // 수정 진입 시 해당 알바 id (없으면 신규)
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
  // 입력 상태
  final _name = TextEditingController();
  final _wage = TextEditingController(text: '0'); // 기본 0원

  String _colorHex = '#3B82F6';
  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy? _surcharge;

  int _startH = 9, _startM = 0;
  int _endH = 18, _endM = 0;
  int _breakMin = 0;

  /// 근무 날짜(UTC 00:00)
  Set<DateTime> _selected = {};

  /// 수정 모드일 때: 해당 알바에 이미 존재하는 날짜(UTC 00:00)
  Set<DateTime> _existingDatesOfEditingAlbaUtc = {};

  /// 급여일(1~31)
  int _payDay = 25;

  bool _showPalette = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _name.text = i.storeName;
      _wage.text = '${i.hourlyWage}';
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
      _payDay = i.payDay;
    }

    // 수정 모드일 때: 이미 있는 날짜들은 충돌 검사에서 제외하기 위해 기억
    if (widget.editingAlbaId != null) {
      _existingDatesOfEditingAlbaUtc = widget.existingSchedules
          .where((s) => s.albaId == widget.editingAlbaId)
          .map((s) => DateTime.utc(s.year, s.month, s.day))
          .toSet();
    }
  }

  bool get _isEdit => widget.initial != null;
  int get _initialWage => widget.initial?.hourlyWage ?? 0;

  Color get _color => cp.parseColor(_colorHex);
  String _fmtAmPm(int h, int m) => cp.fmtAmPm(h, m);
  String _ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /* ───────────────────── 충돌 점검 ───────────────────── */

  // 저장/달력 체크 시: 수정 모드라면 "이미 있던 날짜"는 충돌 제외
  bool _shouldCheckDate(DateTime dUtc) {
    if (widget.editingAlbaId == null) return true;
    return !_existingDatesOfEditingAlbaUtc.contains(dUtc);
  }

  bool _hasConflictOn(DateTime dLocal) {
    final sMin0 = _startH * 60 + _startM;
    var eMin0 = _endH * 60 + _endM;
    final overnight = eMin0 <= sMin0;
    if (overnight) eMin0 += 24 * 60;

    bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
      for (final sc in list) {
        var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
        var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60; // 오버나이트 보정
        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    List<UICalendarSchedule> byYmd(DateTime x) => widget.existingSchedules
        .where((s) => s.year == x.year && s.month == x.month && s.day == x.day)
        .toList();

    final prev = DateTime(dLocal.year, dLocal.month, dLocal.day - 1);
    final next = DateTime(dLocal.year, dLocal.month, dLocal.day + 1);

    final same = byYmd(dLocal);
    final p = byYmd(prev);
    final n = byYmd(next);

    return overlapWith(same, 0) || overlapWith(p, -1) || overlapWith(n, 1);
  }

  /* ───────────────────── 액션 ───────────────────── */

  Future<void> _pickDates() async {
    final res = await showDateAssignSheet(
      context,
      existing: _selected,
      checkConflict: (utc) {
        if (!_shouldCheckDate(utc)) return false; // 수정모드: 기존 날짜는 통과
        return _hasConflictOn(DateTime(utc.year, utc.month, utc.day));
      },
    );
    if (res != null) setState(() => _selected = res.selectedDates);
  }

  Future<void> _pickTimeCupertino() async {
    // 급여일과 같은 톤의 쿠퍼티노 시간 피커
    int sAmpm = _startH < 12 ? 0 : 1; int sHour = (_startH % 12 == 0) ? 12 : _startH % 12; int sMin = _startM;
    int eAmpm = _endH < 12 ? 0 : 1; int eHour = (_endH % 12 == 0) ? 12 : _endH % 12; int eMin = _endM;

    int to24(int ampmIdx, int h12) { if (h12 == 12) h12 = 0; return ampmIdx == 0 ? h12 : h12 + 12; }
    final ampm = const ['오전','오후']; final hours = List<int>.generate(12,(i)=>i+1); final minutes = List<int>.generate(60,(i)=>i);

    await showModalBottomSheet<void>(
      context: context, useSafeArea: true, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                    const Spacer(), const Text('근무시간'), const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() { _startH = to24(sAmpm, sHour); _startM = sMin; _endH = to24(eAmpm, eHour); _endM = eMin; });
                        Navigator.pop(ctx);
                      },
                      child: const Text('완료'),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: Column(children: [
                        Text('시작', style: theme.textTheme.labelLarge), const SizedBox(height: 6),
                        Expanded(child: Row(children: [
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: sAmpm),
                            onSelectedItemChanged: (i) => sAmpm = i, children: ampm.map((t)=>Center(child: Text(t))).toList())),
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: hours.indexOf(sHour)),
                            onSelectedItemChanged: (i) => sHour = hours[i], children: hours.map((h)=>Center(child: Text('$h'))).toList())),
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: sMin),
                            onSelectedItemChanged: (i) => sMin = i, children: minutes.map((m)=>Center(child: Text(m.toString().padLeft(2,'0')))).toList())),
                        ])),
                      ])),
                      const VerticalDivider(width: 1),
                      Expanded(child: Column(children: [
                        Text('종료', style: theme.textTheme.labelLarge), const SizedBox(height: 6),
                        Expanded(child: Row(children: [
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: eAmpm),
                            onSelectedItemChanged: (i) => eAmpm = i, children: ampm.map((t)=>Center(child: Text(t))).toList())),
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: hours.indexOf(eHour)),
                            onSelectedItemChanged: (i) => eHour = hours[i], children: hours.map((h)=>Center(child: Text('$h'))).toList())),
                          Expanded(child: CupertinoPicker(itemExtent: 36,
                            scrollController: FixedExtentScrollController(initialItem: eMin),
                            onSelectedItemChanged: (i) => eMin = i, children: minutes.map((m)=>Center(child: Text(m.toString().padLeft(2,'0')))).toList())),
                        ])),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('${_fmtAmPm(to24(sAmpm, sHour), sMin)} ~ ${_fmtAmPm(to24(eAmpm, eHour), eMin)}',
                    style: theme.textTheme.bodyMedium),
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
    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
    );
    if (r != null) {
      setState(() { _tax = r.tax; _ins = r.ins; _surcharge = r.surcharge; });
    }
  }

  Future<void> _pickPayDay() async {
    final controller = FixedExtentScrollController(initialItem: _payDay - 1);
    final selected = await showModalBottomSheet<int>(
      context: context, useSafeArea: true, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) {
        int tmp = _payDay;
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                    const Spacer(),
                    const Text('급여일'),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(ctx, tmp), child: const Text('완료')),
                  ],
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller, itemExtent: 40,
                    onSelectedItemChanged: (i) => tmp = i + 1,
                    children: List.generate(31, (i) => Center(child: Text('${i + 1}'))),
                  ),
                ),
                const SizedBox(height: 8),
                Text('매월 ${tmp}일', style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _payDay = selected);
  }

  /// “시급 변경 적용 시작일”을 급여일 시트 톤으로 묻는다.
  Future<DateTime?> _askWageEffectiveFrom({DateTime? initial}) async {
    DateTime temp = (initial ?? DateTime.now());
    return showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                    const Spacer(),
                    const Text('시급 적용 시작일'),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(ctx, temp), child: const Text('완료')),
                  ],
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: temp,
                    onDateTimeChanged: (d) =>
                        temp = DateTime(d.year, d.month, d.day),
                  ),
                ),
                const SizedBox(height: 8),
                Text('선택: ${temp.year}.${temp.month.toString().padLeft(2, '0')}.${temp.day.toString().padLeft(2, '0')}'),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSubmit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('매장명을 입력하세요.')));
      return;
    }
    final newWage = int.tryParse(_wage.text.trim()) ?? 0;
    if (newWage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('시급을 확인하세요.')));
      return;
    }

    DateTime? effectiveFrom;
    if (_isEdit && newWage != _initialWage) {
      // 시급 변경 → 적용 시작일을 묻는다(당일 포함).
      effectiveFrom = await _askWageEffectiveFrom(initial: DateTime.now());
      if (effectiveFrom == null) return; // 취소 시 저장 중단
    }

    widget.onSubmit(
      AlbaFormResult(
        storeName: name,
        hourlyWage: newWage,
        colorHex: _colorHex,
        tax: _tax,
        insurance: _ins,
        surcharge: _surcharge,
        startHour24: _startH,
        startMinute: _startM,
        endHour24: _endH,
        endMinute: _endM,
        breakMinutes: _breakMin,
        selectedDates: _selected,
        payDay: _payDay,
        wageEffectiveFrom: effectiveFrom, // ← 적용일 전달
      ),
    );
  }

  /* ───────────────────── UI ───────────────────── */

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: widget.onBack, child: const Text('뒤로')),
        title: Text(_isEdit ? '알바 수정' : '알바 등록'),
        centerTitle: true,
        actions: [ TextButton(onPressed: _onSubmit, child: const Text('완료')) ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 기본 정보
          _Card(
            title: '기본 정보',
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '매장명'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _wage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly], // ← const 금지
                  decoration: const InputDecoration(labelText: '시급(원)'),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showPalette = true),
                  child: Row(
                    children: [
                      Text('표시 색상', style: theme.textTheme.labelLarge),
                      const Spacer(),
                      Container(
                        width: 28, height: 28,
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

          // 정책
          _Card(
            title: '세금/보험/가산정책',
            trailing: TextButton(onPressed: _openPolicy, child: const Text('설정')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('세금: ${_labelTax(_tax)}'),
                Text('보험: ${_labelIns(_ins)}'),
                Text('가산정책: ${_surcharge == null ? "없음" : _summarySurcharge(_surcharge!)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 근무 설정
          _Card(
            title: '근무 설정',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: '근무시간',
                  value:
                    '${_fmtAmPm(_startH, _startM)} ~ ${_fmtAmPm(_endH, _endM)}'
                    '${((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? " (다음날)" : ""}',
                  action: TextButton(onPressed: _pickTimeCupertino, child: const Text('시간 선택')),
                ),
                const SizedBox(height: 8),
                _Line(
                  label: '휴게시간',
                  value: '${_breakMin}분',
                  action: TextButton(onPressed: _pickBreak, child: const Text('설정'))),
                const SizedBox(height: 8),
                _Line(
                  label: '근무 날짜',
                  value: _selected.isEmpty
                    ? '없음'
                    : (_selected.length == 1 ? _ymd(_selected.first) : '${_selected.length}일'),
                  action: TextButton(onPressed: _pickDates, child: const Text('달력 열기')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 급여일
          _Card(
            title: '급여 날짜(매달)',
            trailing: TextButton(onPressed: _pickPayDay, child: const Text('선택')),
            child: Text('선택: 매월 ${_payDay}일'),
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
    if (t == pol.TaxConfig.none) return '없음';
    if (t == pol.TaxConfig.biz33) return '사업소득 3.3%';
    if (t == pol.TaxConfig.day66) return '일용직 6.6%';
    if (t is pol.TaxConfigCustomPercent) {
      return '직접 입력 ${_trimPct(t.percent)}%';
    }
    return '세금 설정';
  }

  String _labelIns(pol.InsuranceConfig i) {
    if (i is pol.InsuranceNone) return '없음';
    if (i is pol.InsuranceEmploymentOnly) return '고용보험만';
    if (i is pol.InsuranceFour) return '4대보험';
    return '보험 설정';
  }

  String _summarySurcharge(pol.SurchargePolicy s) {
    final list = <String>[];
    if (s.weeklyHolidayEnabled) list.add('주휴 ON');
    if (s.overtimeEnabled) list.add('연장 +${_trimPct(s.overtimePercent)}%');
    if (s.holidayEnabled) list.add('휴일 +${_trimPct(s.holidayPercent)}%');
    if (s.nightEnabled) list.add('야간 +${_trimPct(s.nightPercent)}%');
    return list.isEmpty ? '없음' : list.join(', ');
  }
}

/* ── 공용 카드/라인 ── */
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

/* ── 색상 팔레트 다이얼로그 ── */
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
      '#EF4444', '#F97316', '#F59E0B', '#EAB308', '#84CC16',
      '#22C55E', '#10B981', '#06B6D4', '#3B82F6', '#8B5CF6',
    ];

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('색상 선택', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((hex) {
                final selected = hex.toUpperCase() == initialHex.toUpperCase();
                return InkWell(
                  onTap: () => onPick(hex.toUpperCase()),
                  child: Container(
                    width: 40, height: 40,
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
              child: TextButton(onPressed: onDismiss, child: const Text('닫기')),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── 정책 시트 ── */
class polSheetResult {
  final pol.TaxConfig tax;
  final pol.InsuranceConfig ins;
  final pol.SurchargePolicy? surcharge;
  const polSheetResult({required this.tax, required this.ins, this.surcharge});
}

Future<polSheetResult?> showPolicySheet({
  required BuildContext context,
  required pol.TaxConfig initialTax,
  required pol.InsuranceConfig initialIns,
  required pol.SurchargePolicy? initialSurcharge,
}) {
  pol.TaxConfig tax = initialTax;
  pol.InsuranceConfig ins = initialIns;

  bool weekly = initialSurcharge?.weeklyHolidayEnabled ?? false;

  bool overOn = initialSurcharge?.overtimeEnabled ?? false;
  String overPct = _trimPct(initialSurcharge?.overtimePercent ?? 50);

  bool holOn = initialSurcharge?.holidayEnabled ?? false;
  String holPct = _trimPct(initialSurcharge?.holidayPercent ?? 50);

  bool nightOn = initialSurcharge?.nightEnabled ?? false;
  String nightPct = _trimPct(initialSurcharge?.nightPercent ?? 50);

  pol.SurchargePolicy? buildSur() {
    if (!(weekly || overOn || holOn || nightOn)) return null;
    return pol.SurchargePolicy(
      weeklyHolidayEnabled: weekly,
      overtimeEnabled: overOn,
      overtimePercent: int.tryParse(overPct) ?? 0,
      holidayEnabled: holOn,
      holidayPercent: int.tryParse(holPct) ?? 0,
      nightEnabled: nightOn,
      nightPercent: int.tryParse(nightPct) ?? 0,
    );
  }

  String customTax = (initialTax is pol.TaxConfigCustomPercent)
      ? _trimPct(initialTax.percent)
      : '';
  bool customTaxMode = initialTax is pol.TaxConfigCustomPercent;

  return showModalBottomSheet<polSheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return StatefulBuilder(builder: (ctx, setState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                  const Spacer(),
                  Text('세금/보험/가산정책 설정', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      ctx,
                      polSheetResult(tax: tax, ins: ins, surcharge: buildSur()),
                    ),
                    child: const Text('완료'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _Section(
                        title: '세금',
                        child: Column(
                          children: [
                            RadioListTile<pol.TaxConfig>(
                              title: const Text('없음'),
                              value: pol.TaxConfig.none,
                              groupValue: tax,
                              onChanged: (v) => setState(() {
                                tax = v ?? tax;
                                customTaxMode = false;
                              }),
                            ),
                            RadioListTile<pol.TaxConfig>(
                              title: const Text('사업소득 3.3%'),
                              value: pol.TaxConfig.biz33,
                              groupValue: tax,
                              onChanged: (v) => setState(() {
                                tax = v ?? tax;
                                customTaxMode = false;
                              }),
                            ),
                            RadioListTile<pol.TaxConfig>(
                              title: const Text('일용직 6.6%'),
                              value: pol.TaxConfig.day66,
                              groupValue: tax,
                              onChanged: (v) => setState(() {
                                tax = v ?? tax;
                                customTaxMode = false;
                              }),
                            ),
                            ListTile(
                              title: const Text('직접 입력(%)'),
                              trailing: Switch(
                                value: customTaxMode,
                                onChanged: (on) => setState(() {
                                  customTaxMode = on;
                                  tax = on
                                      ? pol.TaxConfigCustomPercent(double.tryParse(customTax) ?? 0.0)
                                      : pol.TaxConfig.none;
                                }),
                              ),
                            ),
                            if (customTaxMode)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                  ], // 소수점 허용
                                  decoration: const InputDecoration(labelText: '세율(%) 예: 5.0'),
                                  controller: TextEditingController(text: customTax)
                                    ..selection = TextSelection.collapsed(offset: customTax.length),
                                  onChanged: (s) => setState(() {
                                    final f = s.replaceAll(RegExp(r'[^0-9.]'), '');
                                    customTax = f;
                                    tax = pol.TaxConfigCustomPercent(double.tryParse(f) ?? 0.0);
                                  }),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Section(
                        title: '보험',
                        child: Column(
                          children: [
                            RadioListTile<pol.InsuranceConfig>(
                              title: const Text('없음'),
                              value: const pol.InsuranceNone(),
                              groupValue: ins,
                              onChanged: (v) => setState(() => ins = v ?? ins),
                            ),
                            RadioListTile<pol.InsuranceConfig>(
                              title: const Text('고용보험만'),
                              value: const pol.InsuranceEmploymentOnly(),
                              groupValue: ins,
                              onChanged: (v) => setState(() => ins = v ?? ins),
                            ),
                            RadioListTile<pol.InsuranceConfig>(
                              title: const Text('4대보험'),
                              value: const pol.InsuranceFour(),
                              groupValue: ins,
                              onChanged: (v) => setState(() => ins = v ?? ins),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Section(
                        title: '가산정책',
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('주휴수당 사용'),
                              value: weekly,
                              onChanged: (on) => setState(() => weekly = on),
                            ),
                            const Divider(),
                            _sRow(
                              ctx,
                              title: '연장근로 수당',
                              on: overOn,
                              pctText: overPct,
                              onToggle: (on) => setState(() => overOn = on),
                              onPct: (txt) => setState(() => overPct = txt),
                            ),
                            const SizedBox(height: 8),
                            _sRow(
                              ctx,
                              title: '휴일 근로 수당',
                              on: holOn,
                              pctText: holPct,
                              onToggle: (on) => setState(() => holOn = on),
                              onPct: (txt) => setState(() => holPct = txt),
                            ),
                            const SizedBox(height: 8),
                            _sRow(
                              ctx,
                              title: '야간 근로 수당 (22:00~06:00)',
                              on: nightOn,
                              pctText: nightPct,
                              onToggle: (on) => setState(() => nightOn = on),
                              onPct: (txt) => setState(() => nightPct = txt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      });
    },
  );
}

Widget _sRow(
  BuildContext ctx, {
  required String title,
  required bool on,
  required String pctText,
  required ValueChanged<bool> onToggle,
  required ValueChanged<String> onPct,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(title)),
          Switch(value: on, onChanged: onToggle),
        ],
      ),
      if (on)
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], // ← const 금지
            decoration: const InputDecoration(labelText: '가산율(%) 예: 50'),
            controller: TextEditingController(text: pctText)
              ..selection = TextSelection.collapsed(offset: pctText.length),
            onChanged: (s) => onPct(s.replaceAll(RegExp(r'[^0-9]'), '')),
          ),
        ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/* ── DTO ── */
class AlbaFormInitial {
  final String storeName;
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  final int breakMinutes;
  final Set<DateTime> selectedDates; // UTC 00:00
  final String colorHex;
  final int payDay;

  AlbaFormInitial({
    required this.storeName,
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
    required this.breakMinutes,
    required this.selectedDates,
    required this.colorHex,
    required this.payDay,
  });
}

class AlbaFormResult {
  final String storeName;
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  final int breakMinutes;
  final Set<DateTime> selectedDates; // UTC 00:00
  final String colorHex;
  final int payDay;

  /// (수정 모드에서 시급을 바꿨다면) 이 날짜 **포함 이후**로 새 시급을 적용.
  final DateTime? wageEffectiveFrom;

  AlbaFormResult({
    required this.storeName,
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
    required this.breakMinutes,
    required this.selectedDates,
    required this.colorHex,
    required this.payDay,
    this.wageEffectiveFrom,
  });
}

/* ── 유틸 ── */
String _trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
