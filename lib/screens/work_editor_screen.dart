import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/ui_calendar_models.dart';
import '../common/common_pickers.dart' as cp;
import 'date_assign_sheet.dart';
import 'work_editor_args.dart' as wargs;
import '../policies/policies.dart' as pol;
import 'alba_form_screen.dart' show showPolicySheet, polSheetResult;

/* ───────────────── 바텀시트 열기 ───────────────── */

Future<void> showWorkEditorSheet({
  required BuildContext context,
  required wargs.WorkEditorArgs args,
  required List<UICalendarAlba> albas,
  required List<UICalendarSchedule> schedules,
  required void Function(UICalendarSchedule s) onAdd,
  required void Function(UICalendarSchedule s) onUpdate,
  required void Function(String scheduleId) onDelete,
  pol.SurchargePolicy? Function(String albaId)? getSurchargePolicy,
  void Function(String albaId, polSheetResult result)? onUpdatePolicy,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _WorkEditorSheet(
        args: args,
        albas: albas,
        schedules: schedules,
        onAdd: onAdd,
        onUpdate: onUpdate,
        onDelete: onDelete,
        getSurchargePolicy: getSurchargePolicy,
        onUpdatePolicy: onUpdatePolicy,
      );
    },
  );
}

/* ───────── push로 들어와도 시트만 띄우고 바로 닫히게 ───────── */

class WorkEditorScreen extends StatefulWidget {
  const WorkEditorScreen({
    super.key,
    required this.args,
    required this.albas,
    required this.schedules,
    required this.getSurchargePolicy,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    required this.onBack,
    this.onUpdatePolicy,
  });

  final wargs.WorkEditorArgs args;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final Object? Function(String albaId) getSurchargePolicy;
  final void Function(UICalendarSchedule s) onAdd;
  final void Function(UICalendarSchedule s) onUpdate;
  final void Function(String scheduleId) onDelete;
  final VoidCallback onBack;
  final void Function(String albaId, polSheetResult result)? onUpdatePolicy;

  @override
  State<WorkEditorScreen> createState() => _WorkEditorScreenState();
}

class _WorkEditorScreenState extends State<WorkEditorScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    Future.microtask(() async {
      await showWorkEditorSheet(
        context: context,
        args: widget.args,
        albas: widget.albas,
        schedules: widget.schedules,
        onAdd: widget.onAdd,
        onUpdate: widget.onUpdate,
        onDelete: widget.onDelete,
        getSurchargePolicy: (id) {
          final obj = widget.getSurchargePolicy(id);
          return (obj is pol.SurchargePolicy) ? obj : null;
        },
        onUpdatePolicy: widget.onUpdatePolicy,
      );
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.transparent, body: SizedBox.shrink());
}

/* ───────────────────────────────────────────────────────────────── */

enum _WorkType { basic, substitute, night, overtime, holiday, weekly }

class _WorkEditorSheet extends StatefulWidget {
  const _WorkEditorSheet({
    required this.args,
    required this.albas,
    required this.schedules,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    this.getSurchargePolicy,
    this.onUpdatePolicy,
  });

  final wargs.WorkEditorArgs args;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final void Function(UICalendarSchedule s) onAdd;
  final void Function(UICalendarSchedule s) onUpdate;
  final void Function(String scheduleId) onDelete;
  final pol.SurchargePolicy? Function(String albaId)? getSurchargePolicy;
  final void Function(String albaId, polSheetResult result)? onUpdatePolicy;

  @override
  State<_WorkEditorSheet> createState() => _WorkEditorSheetState();
}

class _WorkEditorSheetState extends State<_WorkEditorSheet> {
  late final bool _isEdit = widget.args.mode == wargs.WorkEditorArgsMode.edit;

  // 상태
  String _albaId = '';
  Set<DateTime> _selectedUtcDates = {};
  int _startH = 9, _startM = 0, _endH = 18, _endM = 0;
  int _breakMin = 0;
  int? _wageOverride;
  String? _editingScheduleId;
  String? _inlineWarning;

  _WorkType _workType = _WorkType.basic;

  // UI
  bool _previewExpanded = true;

  @override
  void initState() {
    super.initState();

    // 알바 초기값
    if (widget.args.preselectedAlbaId != null &&
        widget.albas.any((a) => a.id == widget.args.preselectedAlbaId)) {
      _albaId = widget.args.preselectedAlbaId!;
    } else if (widget.albas.isNotEmpty) {
      _albaId = widget.albas.first.id;
    }

    // 날짜 초기값
    final preset = widget.args.presetDate ?? DateTime.now();
    _selectedUtcDates = {DateTime.utc(preset.year, preset.month, preset.day)};

    // 수정 로딩
    if (_isEdit && widget.args.scheduleId != null) {
      final s = widget.schedules.firstWhere(
        (x) => x.id == widget.args.scheduleId,
        orElse: () => UICalendarSchedule(
          id: '',
          albaId: _albaId,
          year: preset.year,
          month: preset.month,
          day: preset.day,
          startHour: _startH,
          startMinute: _startM,
          endHour: _endH,
          endMinute: _endM,
          breakMinutes: _breakMin,
        ),
      );
      if (s.id.isNotEmpty) {
        _editingScheduleId = s.id;
        _albaId = s.albaId;
        _startH = s.startHour; _startM = s.startMinute;
        _endH = s.endHour; _endM = s.endMinute;
        _breakMin = s.breakMinutes;
        _selectedUtcDates = {DateTime.utc(s.year, s.month, s.day)};
        _workType = _mapBackToWorkType(s.workType);
        _wageOverride = s.overrideHourlyWage;
      }
    }
  }

  /* ───────── 도우미 ───────── */

  UICalendarAlba? get _alba =>
      widget.albas.firstWhere(
        (a) => a.id == _albaId,
        orElse: () => UICalendarAlba(
          id: '', name: '', colorHex: '#3B82F6', hourlyWage: 0, payDay: 25),
      );

  Color get _albaColor => cp.parseColor(_alba?.colorHex ?? '#3B82F6');

  String _fmtAm(int h, int m) => cp.fmtAmPm(h, m);
  String _ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  int _workedMinutes(int sh, int sm, int eh, int em, int br) {
    final s = sh * 60 + sm;
    var e = eh * 60 + em;
    if (e <= s) e += 24 * 60;
    final w = (e - s) - br;
    return w.clamp(0, 24 * 60);
  }

  String _hoursTextLocal(int minutes) {
    final h = minutes / 60.0;
    final intH = h.floor();
    final isInt = (h - intH).abs() < 0.001;
    return isInt ? '$intH시간' : '${h.toStringAsFixed(1)}시간';
  }

  String _money(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  int _dayPayEstimate(int minutes) {
    final wage = _wageOverride ?? (_alba?.hourlyWage ?? 0);
    return (wage * minutes) ~/ 60;
  }

  pol.SurchargePolicy? _currentSurcharge() =>
      widget.getSurchargePolicy?.call(_albaId);

  /* ───────── 피커(알바 폼 톤 재사용) ───────── */

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
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                    const Spacer(), const Text('근무시간'), const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _startH = to24(sAmpm, sHour); _startM = sMin;
                          _endH = to24(eAmpm, eHour); _endM = eMin;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('완료'),
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
                                      scrollController: FixedExtentScrollController(initialItem: sAmpm),
                                      onSelectedItemChanged: (i) => sAmpm = i,
                                      children: ampm.map((t) => Center(child: Text(t))).toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController: FixedExtentScrollController(initialItem: hours.indexOf(sHour)),
                                      onSelectedItemChanged: (i) => sHour = hours[i],
                                      children: hours.map((h) => Center(child: Text('$h'))).toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController: FixedExtentScrollController(initialItem: sMin),
                                      onSelectedItemChanged: (i) => sMin = i,
                                      children: minutes.map((m) => Center(child: Text(m.toString().padLeft(2, '0')))).toList(),
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
                                      scrollController: FixedExtentScrollController(initialItem: eAmpm),
                                      onSelectedItemChanged: (i) => eAmpm = i,
                                      children: ampm.map((t) => Center(child: Text(t))).toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController: FixedExtentScrollController(initialItem: hours.indexOf(eHour)),
                                      onSelectedItemChanged: (i) => eHour = hours[i],
                                      children: hours.map((h) => Center(child: Text('$h'))).toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoPicker(
                                      itemExtent: 36,
                                      scrollController: FixedExtentScrollController(initialItem: eMin),
                                      onSelectedItemChanged: (i) => eMin = i,
                                      children: minutes.map((m) => Center(child: Text(m.toString().padLeft(2, '0')))).toList(),
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
                  '${_fmtAm(to24(sAmpm, sHour), sMin)} ~ ${_fmtAm(to24(eAmpm, eHour), eMin)}',
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

  Future<void> _pickDates() async {
    final res = await showDateAssignSheet(
      context,
      existing: _selectedUtcDates,
      // 날짜 선택 중에도 모든 알바 기준으로 충돌 미리 표시
      checkConflict: (utc) => _hasAnyConflictOn(DateTime(utc.year, utc.month, utc.day)),
    );
    if (res != null) setState(() => _selectedUtcDates = res.selectedDates.toSet());
  }

  Future<void> _openPolicySheet() async {
    final res = await showPolicySheet(
      context: context,
      initialTax: pol.TaxConfig.none,
      initialIns: const pol.InsuranceNone(),
      initialSurcharge: _currentSurcharge(),
    );
    if (res != null) {
      widget.onUpdatePolicy?.call(_albaId, res);
      setState(() {}); // 갱신
    }
  }

  /* ───────── 겹침 검사(모든 알바 대상, 전일/익일 포함) ───────── */

  bool _hasAnyConflictOn(DateTime localDay) {
    final sMin0 = _startH * 60 + _startM;
    var eMin0 = _endH * 60 + _endM;
    if (eMin0 <= sMin0) eMin0 += 24 * 60;

    bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
      for (final sc in list) {
        if (_editingScheduleId != null && sc.id == _editingScheduleId) continue; // 자기 자신 제외
        var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
        var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60;
        // 반열림 [start, end) 비교: 끝점 맞닿음 허용
        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    List<UICalendarSchedule> byYmd(DateTime x) =>
        widget.schedules.where((s) => s.year == x.year && s.month == x.month && s.day == x.day).toList();

    final same = byYmd(localDay);
    final prev = byYmd(DateTime(localDay.year, localDay.month, localDay.day - 1));
    final next = byYmd(DateTime(localDay.year, localDay.month, localDay.day + 1));

    return overlapWith(same, 0) || overlapWith(prev, -1) || overlapWith(next, 1);
  }

  List<DateTime> _collectConflictDays() {
    final hits = <DateTime>[];
    for (final utc in _selectedUtcDates) {
      final local = DateTime(utc.year, utc.month, utc.day);
      if (_hasAnyConflictOn(local)) hits.add(local);
    }
    hits.sort((a, b) => a.compareTo(b));
    return hits;
  }

  /* ───────── 저장/삭제 ───────── */

  Future<void> _save() async {
    setState(() => _inlineWarning = null);

    if (_albaId.isEmpty) {
      setState(() => _inlineWarning = '알바를 선택하세요.');
      _showInlineWarningIfAny();
      return;
    }
    if (_selectedUtcDates.isEmpty) {
      setState(() => _inlineWarning = '근무 날짜를 선택하세요.');
      _showInlineWarningIfAny();
      return;
    }

    // 🔴 저장 직전 전역 겹침 검사 (모든 알바)
    final conflicts = _collectConflictDays();
    if (conflicts.isNotEmpty) {
      final msg = conflicts.map(_ymd).join(', ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('겹치는 알바가 있습니다'),
          content: Text('$msg 에 같은 시간대의 다른 근무가 있어 저장할 수 없어요.\n시간을 조정한 뒤 다시 시도해 주세요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
          ],
        ),
      );
      return; // ✅ 저장 차단
    }

    if (_isEdit && _editingScheduleId != null) {
      final d = _selectedUtcDates.first;
      final s = UICalendarSchedule(
        id: _editingScheduleId!,
        albaId: _albaId,
        year: d.year, month: d.month, day: d.day,
        startHour: _startH, startMinute: _startM,
        endHour: _endH, endMinute: _endM,
        breakMinutes: _breakMin,
        workType: _mapWorkType(_workType),
        overrideHourlyWage: _wageOverride,
      );
      widget.onUpdate(s);
    } else {
      for (final d in _selectedUtcDates) {
        final s = UICalendarSchedule(
          id: '',
          albaId: _albaId,
          year: d.year, month: d.month, day: d.day,
          startHour: _startH, startMinute: _startM,
          endHour: _endH, endMinute: _endM,
          breakMinutes: _breakMin,
          workType: _mapWorkType(_workType),
          overrideHourlyWage: _wageOverride,
        );
        widget.onAdd(s);
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  void _showInlineWarningIfAny() {
    if (_inlineWarning == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_inlineWarning!), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deleteIfEdit() async {
    if (!_isEdit || _editingScheduleId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 근무를 삭제할까요?'),
        content: const Text('삭제 후 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      widget.onDelete(_editingScheduleId!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /* ───────── UI ───────── */

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeRange =
        '${_fmtAm(_startH, _startM)} ~ ${_fmtAm(_endH, _endM)}'
        '${((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? " (다음날)" : ""}';

    final surcharge = _currentSurcharge();
    final surchargeSummary = () {
      if (surcharge == null) return '없음';
      final l = <String>[];
      if (surcharge.weeklyHolidayEnabled) l.add('주휴 ON');
      if (surcharge.overtimeEnabled) l.add('연장 +${_trimPct(surcharge.overtimePercent)}%');
      if (surcharge.holidayEnabled) l.add('휴일 +${_trimPct(surcharge.holidayPercent)}%');
      if (surcharge.nightEnabled) l.add('야간 +${_trimPct(surcharge.nightPercent)}%');
      return l.isEmpty ? '없음' : l.join(', ');
    }();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(_isEdit ? '근무 수정' : '근무 추가'),
        centerTitle: true,
        actions: [
          if (_isEdit)
            IconButton(tooltip: '삭제', icon: const Icon(Icons.delete_outline), onPressed: _deleteIfEdit),
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            title: '어떤 알바인가요?',
            child: Row(
              children: [
                Flexible(
                  child: DropdownButtonFormField<String>(
                    value: _albaId.isEmpty ? null : _albaId,
                    items: widget.albas.map((a) =>
                      DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _albaId = v ?? ''),
                    decoration: const InputDecoration(
                      hintText: '매장 선택',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28, height: 28,
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _albaColor,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _Card(
            title: '어떤 근무인가요?',
            trailing: TextButton(onPressed: _openPolicySheet, child: const Text('정책 설정')),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                _segButton('기본', _workType == _WorkType.basic, () => setState(() => _workType = _WorkType.basic)),
                _segButton('대타', _WorkType.substitute == _WorkType.substitute && _workType == _WorkType.substitute,
                    () => setState(() => _workType = _WorkType.substitute)),
                _segButton('야간', _workType == _WorkType.night, () => setState(() => _workType = _WorkType.night)),
                _segButton('연장', _workType == _WorkType.overtime, () => setState(() => _workType = _WorkType.overtime)),
                _segButton('휴일', _workType == _WorkType.holiday, () => setState(() => _workType = _WorkType.holiday)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _Card(
            title: '근무 설정',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: '근무시간',
                  value: timeRange,
                  action: TextButton(onPressed: _pickTimeCupertino, child: const Text('시간 선택')),
                ),
                const SizedBox(height: 8),
                _Line(
                  label: '근무 날짜',
                  value: _selectedUtcDates.isEmpty
                      ? '없음'
                      : (_selectedUtcDates.length == 1 ? _ymd(_selectedUtcDates.first) : '${_selectedUtcDates.length}일'),
                  action: TextButton(onPressed: _pickDates, child: const Text('달력 열기')),
                ),
                const SizedBox(height: 8),
                _Line(
                  label: '휴게시간',
                  value: '${_breakMin}분',
                  action: TextButton(onPressed: _pickBreak, child: const Text('설정')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /* ───────── 작은 위젯들 ───────── */

  Widget _segButton(String text, bool selected, VoidCallback onTap) =>
      ChoiceChip(label: Text(text), selected: selected, onSelected: (_) => onTap(), showCheckmark: false);

  WorkType _mapWorkType(_WorkType t) {
    switch (t) {
      case _WorkType.substitute: return WorkType.substitute;
      case _WorkType.night: return WorkType.night;
      case _WorkType.overtime: return WorkType.overtime;
      case _WorkType.holiday: return WorkType.holiday;
      case _WorkType.weekly: return WorkType.basic;
      case _WorkType.basic: default: return WorkType.basic;
    }
  }

  _WorkType _mapBackToWorkType(WorkType t) {
    switch (t) {
      case WorkType.substitute: return _WorkType.substitute;
      case WorkType.night: return _WorkType.night;
      case WorkType.overtime: return _WorkType.overtime;
      case WorkType.holiday: return _WorkType.holiday;
      case WorkType.basic: default: return _WorkType.basic;
    }
  }
}

/* ───────── 공용 카드/라인 ───────── */

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
        Expanded(
          child: Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        action,
      ],
    );
  }
}

/* ───────── 유틸 ───────── */

String _trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
