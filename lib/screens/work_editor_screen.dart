// lib/screens/work_editor_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../common/app_words.dart';
import '../common/common_pickers.dart' as cp;
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart' as pol;
import '../policies/policy_sheet.dart';
import 'date_assign_sheet.dart';
import 'work_editor_args.dart' as wargs;

/* ───────────────── 바텀시트 열기 ───────────────── */

Future<void> showWorkEditorSheet({
  required BuildContext context,
  required wargs.WorkEditorArgs args,
  required List<UICalendarAlba> albas,
  required List<UICalendarSchedule> schedules,
  required Future<void> Function(UICalendarSchedule s) onAdd,
  required Future<void> Function(UICalendarSchedule s) onUpdate,
  required Future<void> Function(String scheduleId) onDelete,
  pol.SurchargePolicy? Function(String albaId)? getSurchargePolicy,
  Future<void> Function(String albaId, PolicySheetResult result)?
      onUpdatePolicy,
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

/* ───────────────────────────────────────────────────────────────── */

enum _WorkType { basic, substitute, night, overtime, holiday }

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

  final Future<void> Function(UICalendarSchedule s) onAdd;
  final Future<void> Function(UICalendarSchedule s) onUpdate;
  final Future<void> Function(String scheduleId) onDelete;

  final pol.SurchargePolicy? Function(String albaId)? getSurchargePolicy;
  final Future<void> Function(String albaId, PolicySheetResult result)?
      onUpdatePolicy;

  @override
  State<_WorkEditorSheet> createState() => _WorkEditorSheetState();
}

class _WorkEditorSheetState extends State<_WorkEditorSheet> {
  late final bool _isEdit = widget.args.mode == wargs.WorkEditorArgsMode.edit;

  String _albaId = '';
  Set<DateTime> _selectedUtcDates = {};
  int _startH = 9, _startM = 0, _endH = 18, _endM = 0;
  int _breakMin = 0;

  String? _editingScheduleId;

  bool _saving = false;
  _WorkType _workType = _WorkType.basic;

  @override
  void initState() {
    super.initState();

    if (widget.args.preselectedAlbaId != null &&
        widget.albas.any((a) => a.id == widget.args.preselectedAlbaId)) {
      _albaId = widget.args.preselectedAlbaId!;
    } else if (widget.albas.isNotEmpty) {
      _albaId = widget.albas.first.id;
    }

    final preset = widget.args.presetDate ?? DateTime.now();
    _selectedUtcDates = {DateTime.utc(preset.year, preset.month, preset.day)};

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
          workType: WorkType.basic,
        ),
      );

      if (s.id.isNotEmpty) {
        _editingScheduleId = s.id;
        _albaId = s.albaId;
        _startH = s.startHour;
        _startM = s.startMinute;
        _endH = s.endHour;
        _endM = s.endMinute;
        _breakMin = s.breakMinutes;
        _selectedUtcDates = {DateTime.utc(s.year, s.month, s.day)};
        _workType = _mapBackToWorkType(s.workType);
        // ✅ 시급 override UI 제거: 기존 값이 있어도 편집 화면에서는 다루지 않음
      }
    }
  }

  UICalendarAlba get _alba => widget.albas.firstWhere(
        (a) => a.id == _albaId,
        orElse: () => const UICalendarAlba(
          id: '',
          name: '',
          colorHex: '#3B82F6',
          hourlyWage: 0,
          payDay: 25,
        ),
      );

  Color get _albaColor => cp.parseColor(_alba.colorHex);

  String _fmtAm(int h, int m) => cp.fmtAmPm(h, m);

  String _ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  pol.SurchargePolicy? _currentSurcharge() =>
      widget.getSurchargePolicy?.call(_albaId);

  String get _timeRangeText {
    final base = '${_fmtAm(_startH, _startM)} ~ ${_fmtAm(_endH, _endM)}';
    final crosses =
        ((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? true : false;
    return crosses ? '$base ${AppWords.nextDaySuffix}' : base;
  }

  String get _datesText {
    if (_selectedUtcDates.isEmpty) return AppWords.none;
    if (_selectedUtcDates.length == 1) return _ymd(_selectedUtcDates.first);
    return '${_selectedUtcDates.length}${AppWords.dayUnit}';
  }

  String get _breakText => '${_breakMin}${AppWords.minuteUnit}';

  String get _typeLabel {
    switch (_workType) {
      case _WorkType.basic:
        return AppWords.workTypeBasic;
      case _WorkType.substitute:
        return AppWords.workTypeSubstitute;
      case _WorkType.night:
        return AppWords.workTypeNight;
      case _WorkType.overtime:
        return AppWords.workTypeOvertime;
      case _WorkType.holiday:
        return AppWords.workTypeHoliday;
    }
  }

  /* ───────────────── Picker / Sheet ───────────────── */

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(ctx),
                        child: const Text(AppWords.cancel),
                      ),
                      const Spacer(),
                      Text(
                        AppWords.workTime,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                setState(() {
                                  _startH = to24(sAmpm, sHour);
                                  _startM = sMin;
                                  _endH = to24(eAmpm, eHour);
                                  _endM = eMin;
                                });
                                Navigator.pop(ctx);
                              },
                        child: const Text(AppWords.done),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _PickerBlock(
                          title: AppWords.workStart,
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoPicker(
                                  itemExtent: 36,
                                  scrollController: FixedExtentScrollController(
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
                                  scrollController: FixedExtentScrollController(
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
                                  scrollController: FixedExtentScrollController(
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
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _PickerBlock(
                          title: AppWords.workEnd,
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoPicker(
                                  itemExtent: 36,
                                  scrollController: FixedExtentScrollController(
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
                                  scrollController: FixedExtentScrollController(
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
                                  scrollController: FixedExtentScrollController(
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmtAm(to24(sAmpm, sHour), sMin)} ~ ${_fmtAm(to24(eAmpm, eHour), eMin)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
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
      checkConflict: (utc) =>
          _hasAnyConflictOn(DateTime(utc.year, utc.month, utc.day)),
    );
    if (res != null) {
      setState(() => _selectedUtcDates = res.selectedDates.toSet());
    }
  }

  Future<void> _openPolicySheet() async {
    final res = await showPolicySheet(
      context: context,
      initialTax: pol.TaxConfig.none,
      initialIns: const pol.InsuranceNone(),
      initialSurcharge: _currentSurcharge(),
    );

    if (res != null) {
      if (widget.onUpdatePolicy != null) {
        setState(() => _saving = true);
        try {
          await widget.onUpdatePolicy!.call(_albaId, res);
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      }
      setState(() {});
    }
  }

  /* ───────────────── Conflict Check ───────────────── */

  bool _hasAnyConflictOn(DateTime localDay) {
    final sMin0 = _startH * 60 + _startM;
    var eMin0 = _endH * 60 + _endM;
    if (eMin0 <= sMin0) eMin0 += 24 * 60;

    bool overlapWith(List<UICalendarSchedule> list, int dayOffset) {
      for (final sc in list) {
        if (_editingScheduleId != null && sc.id == _editingScheduleId) continue;

        var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
        var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60;

        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    List<UICalendarSchedule> byYmd(DateTime x) => widget.schedules
        .where((s) => s.year == x.year && s.month == x.month && s.day == x.day)
        .toList();

    final same = byYmd(localDay);
    final prev =
        byYmd(DateTime(localDay.year, localDay.month, localDay.day - 1));
    final next =
        byYmd(DateTime(localDay.year, localDay.month, localDay.day + 1));

    return overlapWith(same, 0) ||
        overlapWith(prev, -1) ||
        overlapWith(next, 1);
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

  /* ───────────────── Save / Delete ───────────────── */

  Future<void> _save() async {
    if (_saving) return;

    if (_albaId.isEmpty) {
      _showSnack(AppWords.workPickAlbaWarn);
      return;
    }
    if (_selectedUtcDates.isEmpty) {
      _showSnack(AppWords.workPickDateWarn);
      return;
    }

    final conflicts = _collectConflictDays();
    if (conflicts.isNotEmpty) {
      final msg = conflicts.map(_ymd).join(', ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppWords.workConflictTitle),
          content: Text(
            '${AppWords.workConflictBodyPrefix}$msg${AppWords.workConflictBodySuffix}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppWords.ok),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit && _editingScheduleId != null) {
        final d = _selectedUtcDates.first;
        await widget.onUpdate(
          UICalendarSchedule(
            id: _editingScheduleId!,
            albaId: _albaId,
            year: d.year,
            month: d.month,
            day: d.day,
            startHour: _startH,
            startMinute: _startM,
            endHour: _endH,
            endMinute: _endM,
            breakMinutes: _breakMin,
            workType: _mapWorkType(_workType),
            overrideHourlyWage: null, // ✅ 시급 설정 UI 제거
          ),
        );
      } else {
        for (final d in _selectedUtcDates) {
          await widget.onAdd(
            UICalendarSchedule(
              id: '',
              albaId: _albaId,
              year: d.year,
              month: d.month,
              day: d.day,
              startHour: _startH,
              startMinute: _startM,
              endHour: _endH,
              endMinute: _endM,
              breakMinutes: _breakMin,
              workType: _mapWorkType(_workType),
              overrideHourlyWage: null, // ✅ 시급 설정 UI 제거
            ),
          );
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.saveFailed}\n$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deleteIfEdit() async {
    if (_saving) return;
    if (!_isEdit || _editingScheduleId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppWords.workDeleteConfirmTitle),
        content: const Text(AppWords.workDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppWords.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppWords.delete),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.onDelete(_editingScheduleId!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.deleteFailed}\n$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /* ───────────────── UI ───────────────── */

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 선택 날짜 미리보기 (멀티)
    final sortedDates = _selectedUtcDates.toList()
      ..sort((a, b) => a.compareTo(b));
    final datePreview = sortedDates.take(3).map(_ymd).toList();
    final more = sortedDates.length - datePreview.length;

    return IgnorePointer(
      ignoring: _saving,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                  _isEdit ? AppWords.workEditTitle : AppWords.workAddTitle),
              centerTitle: true,
              actions: [
                if (_isEdit)
                  IconButton(
                    tooltip: AppWords.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _deleteIfEdit,
                  ),
              ],
            ),
            body: SafeArea(
              top: false,
              bottom: true,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      children: [
                        // ✅ 상단 “요약 카드”
                        _TossCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  _ColorDot(color: _albaColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _alba.name.isEmpty
                                          ? AppWords.workPickAlbaTitle
                                          : _alba.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _Pill(
                                    text: _typeLabel,
                                    bg: _albaColor.withOpacity(0.10),
                                    fg: theme.colorScheme.onSurface
                                        .withOpacity(0.75),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _SummaryRow(
                                icon: Icons.schedule_rounded,
                                title: AppWords.workTime,
                                value: _timeRangeText,
                              ),
                              const SizedBox(height: 6),
                              _SummaryRow(
                                icon: Icons.event_available_rounded,
                                title: AppWords.workDate,
                                value: _datesText,
                                sub: sortedDates.length <= 1
                                    ? null
                                    : '${datePreview.join(' · ')}${more > 0 ? ' · +$more' : ''}',
                              ),
                              const SizedBox(height: 6),
                              _SummaryRow(
                                icon: Icons.coffee_rounded,
                                title: AppWords.breakTime,
                                value: _breakText,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ✅ “수정 섹션” (탭 가능한 Row)
                        _TossCard(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          child: Column(
                            children: [
                              _TapRow(
                                title: AppWords.workPickAlbaTitle,
                                value: _alba.name.isEmpty
                                    ? AppWords.none
                                    : _alba.name,
                                leading: _ColorDot(color: _albaColor),
                                onTap: () async {
                                  await showModalBottomSheet<void>(
                                    context: context,
                                    useSafeArea: true,
                                    showDragHandle: true,
                                    builder: (ctx) {
                                      return _AlbaPickerSheet(
                                        albas: widget.albas,
                                        selectedId: _albaId,
                                        onPick: (id) {
                                          setState(() => _albaId = id);
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              _TapRow(
                                title: AppWords.workPickTypeTitle,
                                value: _typeLabel,
                                leadingIcon: Icons.category_rounded,
                                trailing: TextButton(
                                  onPressed: _openPolicySheet,
                                  child: const Text(AppWords.workPolicyOpen),
                                ),
                                onTap: () async {
                                  final picked =
                                      await showModalBottomSheet<_WorkType>(
                                    context: context,
                                    useSafeArea: true,
                                    showDragHandle: true,
                                    builder: (ctx) => _WorkTypeSheet(
                                      current: _workType,
                                      albaColor: _albaColor,
                                    ),
                                  );
                                  if (picked != null) {
                                    setState(() => _workType = picked);
                                  }
                                },
                              ),
                              const Divider(height: 1),
                              _TapRow(
                                title: AppWords.workTime,
                                value: _timeRangeText,
                                leadingIcon: Icons.schedule_rounded,
                                onTap: _pickTimeCupertino,
                              ),
                              const Divider(height: 1),
                              _TapRow(
                                title: AppWords.workDate,
                                value: _datesText,
                                leadingIcon: Icons.event_rounded,
                                sub: sortedDates.length <= 1
                                    ? null
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final t in datePreview)
                                            _MiniChip(text: t),
                                          if (more > 0)
                                            _MiniChip(text: '+$more'),
                                        ],
                                      ),
                                onTap: _pickDates,
                              ),
                              const Divider(height: 1),
                              _TapRow(
                                title: AppWords.breakTime,
                                value: _breakText,
                                leadingIcon: Icons.coffee_rounded,
                                onTap: _pickBreak,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ✅ 하단 큰 저장 버튼 (토스식)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _isEdit ? AppWords.save : AppWords.save,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.10),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  WorkType _mapWorkType(_WorkType t) {
    switch (t) {
      case _WorkType.substitute:
        return WorkType.substitute;
      case _WorkType.night:
        return WorkType.night;
      case _WorkType.overtime:
        return WorkType.overtime;
      case _WorkType.holiday:
        return WorkType.holiday;
      case _WorkType.basic:
      default:
        return WorkType.basic;
    }
  }

  _WorkType _mapBackToWorkType(WorkType t) {
    switch (t) {
      case WorkType.substitute:
        return _WorkType.substitute;
      case WorkType.night:
        return _WorkType.night;
      case WorkType.overtime:
        return _WorkType.overtime;
      case WorkType.holiday:
        return _WorkType.holiday;
      case WorkType.basic:
      default:
        return _WorkType.basic;
    }
  }
}

/* ───────────────── 작은 컴포넌트들 ───────────────── */

class _TossCard extends StatelessWidget {
  const _TossCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: fg,
            ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 18, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(
                  sub!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.title,
    required this.value,
    required this.onTap,
    this.leading,
    this.leadingIcon,
    this.trailing,
    this.sub,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  final Widget? leading;
  final IconData? leadingIcon;

  final Widget? trailing;
  final Widget? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(padding: const EdgeInsets.only(top: 3), child: leading!),
              const SizedBox(width: 10),
            ] else if (leadingIcon != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  leadingIcon,
                  size: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 8),
                    sub!,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.35),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface.withOpacity(0.75),
        ),
      ),
    );
  }
}

class _PickerBlock extends StatelessWidget {
  const _PickerBlock({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          title,
          style:
              theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }
}

/* ───────────────── 알바 선택 시트 ───────────────── */

class _AlbaPickerSheet extends StatelessWidget {
  const _AlbaPickerSheet({
    required this.albas,
    required this.selectedId,
    required this.onPick,
  });

  final List<UICalendarAlba> albas;
  final String selectedId;
  final void Function(String albaId) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Text(
                  AppWords.workPickAlbaTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: albas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final a = albas[i];
                final c = cp.parseColor(a.colorHex);
                final on = a.id == selectedId;

                return ListTile(
                  leading: _ColorDot(color: c),
                  title: Text(
                    a.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  trailing: on ? const Icon(Icons.check_rounded) : null,
                  onTap: () => onPick(a.id),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/* ───────────────── 근무 타입 선택 시트 ───────────────── */

class _WorkTypeSheet extends StatelessWidget {
  const _WorkTypeSheet({
    required this.current,
    required this.albaColor,
  });

  final _WorkType current;
  final Color albaColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget tile(_WorkType t, String label, IconData icon) {
      final on = t == current;
      return ListTile(
        leading: Icon(icon,
            color:
                on ? albaColor : theme.colorScheme.onSurface.withOpacity(0.65)),
        title: Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: on ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        trailing: on ? const Icon(Icons.check_rounded) : null,
        onTap: () => Navigator.pop(context, t),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Text(
                  AppWords.workPickTypeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          tile(_WorkType.basic, AppWords.workTypeBasic, Icons.work_rounded),
          tile(_WorkType.substitute, AppWords.workTypeSubstitute,
              Icons.swap_horiz_rounded),
          tile(_WorkType.night, AppWords.workTypeNight, Icons.nightlight_round),
          tile(_WorkType.overtime, AppWords.workTypeOvertime,
              Icons.timer_rounded),
          tile(_WorkType.holiday, AppWords.workTypeHoliday, Icons.beach_access),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
