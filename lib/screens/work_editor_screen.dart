// lib/screens/work_editor_screen.dart
import 'package:flutter/material.dart';

import '../common/app_words.dart';
import '../common/paymoa_design.dart';
import '../common/common_pickers.dart' as cp;
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart' as pol;
import '../policies/policy_sheet.dart';
import 'date_assign_sheet.dart';
import 'work_editor_args.dart' as wargs;
import '../ads/ad_service.dart';
import '../services/last_work_time_service.dart';

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
  int Function(String albaId, DateTime date)? wageAt,
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
        wageAt: wageAt,
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
    this.wageAt,
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

  final int Function(String albaId, DateTime date)? wageAt;

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
  String? _editingDocPath;
  DateTime? _originalDate;

  bool _saving = false;
  _WorkType _workType = _WorkType.basic;
  int? _overrideWage;

  bool get _hasAlbas => widget.albas.isNotEmpty;

  bool get _isStoreAlba {
    final alba = _alba;
    return alba.storeId.isNotEmpty;
  }

  String get _selectedAlbaId {
    if (_albaId.isNotEmpty) return _albaId;
    if (widget.albas.isNotEmpty) return widget.albas.first.id;
    return '';
  }

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

    if (!_isEdit) {
      _loadLastWorkTime(_selectedAlbaId);
    }

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
        _editingDocPath = s.docPath;
        _albaId = s.albaId;
        _startH = s.startHour;
        _startM = s.startMinute;
        _endH = s.endHour;
        _endM = s.endMinute;
        _breakMin = s.breakMinutes;
        _selectedUtcDates = {DateTime.utc(s.year, s.month, s.day)};
        _originalDate = DateTime(s.year, s.month, s.day);
        _workType = _mapBackToWorkType(s.workType);
        _overrideWage = s.overrideHourlyWage;
      }
    }
  }

  Future<void> _loadLastWorkTime(String albaId) async {
    final saved = await LastWorkTimeService.load(albaId);
    if (saved == null || !mounted) return;
    setState(() {
      _startH = saved.startH;
      _startM = saved.startM;
      _endH = saved.endH;
      _endM = saved.endM;
      _breakMin = saved.breakMin;
    });
  }

  UICalendarAlba get _alba => widget.albas.firstWhere(
        (a) => a.id == _selectedAlbaId,
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
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  pol.SurchargePolicy? _currentSurcharge() =>
      widget.getSurchargePolicy?.call(_albaId);

  String get _timeRangeText {
    final base = '${_fmtAm(_startH, _startM)} ~ ${_fmtAm(_endH, _endM)}';
    final crosses =
        ((_endH * 60 + _endM) <= (_startH * 60 + _startM)) ? true : false;
    return crosses ? '$base ${AppWords.nextDaySuffix}' : base;
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

  String get _appBarTitle {
    if (_isEdit) return AppWords.workEditTitle;
    final preset = widget.args.presetDate;
    if (preset != null) {
      return '${preset.month}월 ${preset.day}일 근무 추가';
    }
    return AppWords.workAddTitle;
  }

  /* ───────────────── Picker / Sheet ───────────────── */

  Future<void> _pickTimeCupertino() async {
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
    await cp.showBreakSheet(
      context: context,
      initialMinutes: _breakMin,
      onDone: (m) {
        if (!mounted) return;
        setState(() => _breakMin = m);
      },
    );
  }

  Future<void> _pickDates() async {
    final res = await showDateAssignSheet(
      context,
      existing: _selectedUtcDates,
      checkConflict: (utc) =>
          _hasAnyConflictOn(DateTime(utc.year, utc.month, utc.day)),
    );
    if (!mounted || res == null) return;

    setState(() => _selectedUtcDates = res.selectedDates.toSet());
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              AppWords.delete,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFF43F5E),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.onDelete(_editingScheduleId!);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '삭제에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveTapped() {
    AdService.instance.showRewardedAd(
      onRewarded: _save,
      onNotReady: _save,
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!_hasAlbas) {
      _showSnack('등록된 알바가 없어요.');
      return;
    }

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
      if (!mounted) return;
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit && _editingScheduleId != null) {
        final d = _selectedUtcDates.first;
        final newDate = DateTime(d.year, d.month, d.day);

        int? resolvedWage = _overrideWage;
        if (_originalDate != null && newDate != _originalDate) {
          resolvedWage = widget.wageAt?.call(_albaId, newDate);
        }

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
            overrideHourlyWage: resolvedWage,
            docPath: _editingDocPath,
          ),
        );
      } else {
        for (final d in _selectedUtcDates) {
          final localDate = DateTime(d.year, d.month, d.day);
          final resolvedWage = widget.wageAt?.call(_albaId, localDate);

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
              overrideHourlyWage: resolvedWage,
            ),
          );
        }
      }

      await LastWorkTimeService.save(
        albaId: _albaId,
        startH: _startH,
        startM: _startM,
        endH: _endH,
        endM: _endM,
        breakMin: _breakMin,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '저장에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  /* ───────────────── UI ───────────────── */

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sortedDates = _selectedUtcDates.toList()
      ..sort((a, b) => a.compareTo(b));

    return IgnorePointer(
      ignoring: _saving,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Pm.fieldBg,
            appBar: AppBar(
              backgroundColor: Pm.fieldBg,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
              title: Text(_appBarTitle),
              centerTitle: true,
              actions: [
                if (_isEdit)
                  IconButton(
                    tooltip: AppWords.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _saving ? null : _deleteIfEdit,
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
                                onTap: !_hasAlbas
                                    ? () => _showSnack('등록된 알바가 없어요.')
                                    : () async {
                                        final picked =
                                            await showModalBottomSheet<String>(
                                          context: context,
                                          useSafeArea: true,
                                          showDragHandle: true,
                                          builder: (ctx) {
                                            return _AlbaPickerSheet(
                                              albas: widget.albas,
                                              selectedId: _albaId,
                                              onPick: (id) =>
                                                  Navigator.pop(ctx, id),
                                            );
                                          },
                                        );
                                        if (!mounted || picked == null) return;
                                        setState(() => _albaId = picked);
                                        _loadLastWorkTime(picked);
                                      },
                              ),
                              const Divider(height: 1),
                              _TapRow(
                                title: AppWords.workPickTypeTitle,
                                value: _typeLabel,
                                leadingIcon: Icons.category_rounded,
                                onTap: () async {
                                  final picked =
                                      await showModalBottomSheet<_WorkType>(
                                    context: context,
                                    useSafeArea: true,
                                    showDragHandle: true,
                                    builder: (ctx) => _WorkTypeSheet(
                                      current: _workType,
                                      albaColor: _albaColor,
                                      surcharge: _currentSurcharge(),
                                    ),
                                  );
                                  if (!mounted || picked == null) return;
                                  setState(() => _workType = picked);
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
                                value: '총 ${_selectedUtcDates.length}일',
                                leadingIcon: Icons.event_rounded,
                                sub: _selectedUtcDates.isEmpty
                                    ? null
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final t in sortedDates)
                                            _MiniChip(text: _ymd(t)),
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
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _saving ? null : _saveTapped,
                          style: FilledButton.styleFrom(
                            backgroundColor: Pm.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Pm.radiusBtn),
                            ),
                          ),
                          child: Text(
                            AppWords.save,
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

class _WorkTypeSheet extends StatelessWidget {
  const _WorkTypeSheet({
    required this.current,
    required this.albaColor,
    this.surcharge,
  });

  final _WorkType current;
  final Color albaColor;
  final pol.SurchargePolicy? surcharge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sur = surcharge;

    Widget tile(_WorkType t, String label, IconData icon) {
      final on = t == current;
      return ListTile(
        leading: Icon(
          icon,
          color: on ? albaColor : theme.colorScheme.onSurface.withOpacity(0.65),
        ),
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
          tile(
            _WorkType.substitute,
            AppWords.workTypeSubstitute,
            Icons.swap_horiz_rounded,
          ),
          if (sur != null && sur.nightEnabled)
            tile(_WorkType.night, AppWords.workTypeNight,
                Icons.nightlight_round),
          if (sur != null && sur.overtimeEnabled)
            tile(_WorkType.overtime, AppWords.workTypeOvertime,
                Icons.timer_rounded),
          if (sur != null && sur.holidayEnabled)
            tile(_WorkType.holiday, AppWords.workTypeHoliday,
                Icons.beach_access),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _WageOptionTile extends StatelessWidget {
  const _WageOptionTile({
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
