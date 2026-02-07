// lib/screens/alba_start_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../common/app_words.dart';
import '../models/ui_calendar_models.dart';
import '../common/common_pickers.dart' as cp;
import '../policies/policies.dart' as pol;
import 'work_editor_args.dart' as wargs;

// payroll
import '../payroll/payroll.dart';

// join sheet
import 'join_store_sheet.dart';

// form
import 'alba_form_screen.dart';
import '../models/alba_form_models.dart';

/* ───────────────────────── 공용 헬퍼 ───────────────────────── */

class _DotEvent {
  final Color color;
  final String albaName;
  const _DotEvent(this.color, this.albaName);
}

String _fmtHm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String _timeRangeText(int sh, int sm, int eh, int em) {
  final s = sh * 60 + sm, e = eh * 60 + em;
  final next = (e <= s) ? ' (다음날)' : '';
  return '${_fmtHm(sh, sm)}~${_fmtHm(eh, em)}$next';
}

String _hoursText(int minutes) {
  final h = minutes / 60.0;
  final intH = h.floor();
  final isInt = (h - intH).abs() < 0.001;
  return isInt ? '$intH시간' : '${h.toStringAsFixed(1)}시간';
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

String _trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _workTypeLabel(WorkType t) {
  switch (t) {
    case WorkType.basic:
      return AppWords.workTypeBasic;
    case WorkType.substitute:
      return AppWords.workTypeSubstitute;
    case WorkType.overtime:
      return AppWords.workTypeOvertime;
    case WorkType.holiday:
      return AppWords.workTypeHoliday;
    case WorkType.night:
      return AppWords.workTypeNight;
  }
}

/// ✅ 시간순으로 workType 라벨을 +로 묶기 (대타+기본 / 기본+대타)
String _typeLabelByTime(List<UICalendarSchedule> children) {
  final sorted = [...children]..sort((a, b) {
      final amn = a.startHour * 60 + a.startMinute;
      final bmn = b.startHour * 60 + b.startMinute;
      if (amn != bmn) return amn.compareTo(bmn);
      return a.id.compareTo(b.id);
    });

  final seen = <WorkType>{};
  final labels = <String>[];
  for (final s in sorted) {
    if (seen.add(s.workType)) labels.add(_workTypeLabel(s.workType));
  }
  return labels.join('+');
}

/* ───────────────────────── Toss Tone UI ───────────────────────── */

class _TossCard extends StatelessWidget {
  const _TossCard({
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final Widget child;
  final Color accent;
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
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.95),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 6).add(padding),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.text,
    required this.selected,
    required this.isToday,
  });

  final String text;
  final bool selected;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ 톤다운 포인트:
    // - 선택: primary(쨍한 파랑) 대신 primaryContainer(부드러운 파랑/회색) 사용
    // - 오늘: 아주 옅은 틴트 + 얇은 테두리
    final bg = selected
        ? theme.colorScheme.primaryContainer
        : isToday
            ? theme.colorScheme.primary.withOpacity(0.06)
            : Colors.transparent;

    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface.withOpacity(0.88);

    final border = (!selected && isToday)
        ? Border.all(
            color: theme.colorScheme.primary.withOpacity(0.22),
            width: 1.1,
          )
        : null;

    return Center(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────── 병합 블록/카드 ───────────────────────── */

class _MergedBlock {
  _MergedBlock({
    required this.albaId,
    required this.year,
    required this.month,
    required this.day,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.totalBreakMinutes,
    required this.scheduleIds,
    required this.types,
    required this.children,
  });

  final String albaId;
  final int year, month, day;
  int startHour, startMinute;
  int endHour, endMinute;
  int totalBreakMinutes;
  final List<String> scheduleIds;
  final Set<WorkType> types;
  final List<UICalendarSchedule> children;

  factory _MergedBlock.fromSingle(UICalendarSchedule s) {
    return _MergedBlock(
      albaId: s.albaId,
      year: s.year,
      month: s.month,
      day: s.day,
      startHour: s.startHour,
      startMinute: s.startMinute,
      endHour: s.endHour,
      endMinute: s.endMinute,
      totalBreakMinutes: s.breakMinutes,
      scheduleIds: [s.id],
      types: {s.workType},
      children: [s],
    );
  }

  int get startMinutes => startHour * 60 + startMinute;
  int get endMinutes => endHour * 60 + endMinute;

  bool isContiguousWith(UICalendarSchedule s) {
    if (s.albaId != albaId ||
        s.year != year ||
        s.month != month ||
        s.day != day) return false;
    return endMinutes == (s.startHour * 60 + s.startMinute);
  }

  void absorb(UICalendarSchedule s) {
    endHour = s.endHour;
    endMinute = s.endMinute;
    totalBreakMinutes += s.breakMinutes;
    scheduleIds.add(s.id);
    types.add(s.workType);
    children.add(s);
  }

  int get totalWorkedMinutes {
    final start = Duration(hours: startHour, minutes: startMinute);
    var end = Duration(hours: endHour, minutes: endMinute);
    var diff = end - start;
    if (diff.isNegative) diff += const Duration(days: 1);
    final worked = diff.inMinutes - totalBreakMinutes.clamp(0, diff.inMinutes);
    return worked.clamp(0, 24 * 60);
  }
}

class _ExpandableMergedCard extends StatefulWidget {
  const _ExpandableMergedCard({
    required this.alba,
    required this.color,
    required this.block,
    required this.localDate,
    required this.onEdit,
    required this.onDelete,
  });

  final UICalendarAlba alba;
  final Color color;
  final _MergedBlock block;
  final DateTime localDate;

  final void Function(String scheduleId) onEdit;
  final void Function(String scheduleId) onDelete;

  @override
  State<_ExpandableMergedCard> createState() => _ExpandableMergedCardState();
}

class _ExpandableMergedCardState extends State<_ExpandableMergedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.block;

    final totalHoursText = _hoursText(b.totalWorkedMinutes);
    final typeLabel = _typeLabelByTime(b.children);

    final lines = [...b.children]..sort((a, b) {
        final amn = a.startHour * 60 + a.startMinute;
        final bmn = b.startHour * 60 + b.startMinute;
        if (amn != bmn) return amn.compareTo(bmn);
        return a.id.compareTo(b.id);
      });

    return _TossCard(
      accent: widget.color,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.alba.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${_timeRangeText(s.startHour, s.startMinute, s.endHour, s.endMinute)}  ·  ${_workTypeLabel(s.workType)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totalHoursText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
              child: Column(
                children: [
                  Divider(
                      height: 1, color: theme.dividerColor.withOpacity(0.35)),
                  const SizedBox(height: 6),
                  ...lines.map((s) {
                    final st = _fmtHm(s.startHour, s.startMinute);
                    final et = _fmtHm(s.endHour, s.endMinute);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      dense: true,
                      title: Text(
                        '$st~$et (${_workTypeLabel(s.workType)})',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: AppWords.delete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.onDelete(s.id),
                          ),
                          TextButton(
                            onPressed: () => widget.onEdit(s.id),
                            child: const Text(AppWords.edit),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/* ───────────────────────── 화면 ───────────────────────── */

class AlbaStartScreen extends StatefulWidget {
  const AlbaStartScreen({
    super.key,
    required this.albas,
    required this.schedules,
    required this.onBack,
    required this.onGoToAlbaForm,
    required this.onEditAlba,
    required this.onOpenWorkEditor,
    required this.onDeleteSchedule,
    required this.onDeleteAlba,
    this.onJoinSubmit,
    this.getTaxPolicy,
    this.getInsurancePolicy,
    this.getSurchargePolicy,
    this.getPayrollPolicy,
  });

  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final VoidCallback onBack;

  final VoidCallback onGoToAlbaForm;

  final void Function(String albaId) onEditAlba;
  final void Function(wargs.WorkEditorArgs) onOpenWorkEditor;

  final Future<void> Function(String scheduleId) onDeleteSchedule;
  final void Function(String albaId) onDeleteAlba;

  final Future<void> Function(
    JoinStoreSheetResult sheet,
    String workerName,
    String? storeAliasName,
    AlbaFormResult form,
  )? onJoinSubmit;

  final Object? Function(String albaId)? getTaxPolicy;
  final Object? Function(String albaId)? getInsurancePolicy;
  final Object? Function(String albaId)? getSurchargePolicy;
  final PayrollPolicy? Function(String albaId)? getPayrollPolicy;

  @override
  State<AlbaStartScreen> createState() => _AlbaStartScreenState();
}

class _AlbaStartScreenState extends State<AlbaStartScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  bool _joinSaving = false;

  int _dotsCacheHash = 0;
  Map<DateTime, List<_DotEvent>> _dotsByDay = const {};

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = null;
    _rebuildDotsCacheIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AlbaStartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildDotsCacheIfNeeded();
  }

  int _calcSchedulesHash() {
    return Object.hash(
      widget.schedules.length,
      Object.hashAll(widget.schedules.map((s) => s.id)),
    );
  }

  void _rebuildDotsCacheIfNeeded() {
    final h = _calcSchedulesHash();
    if (h == _dotsCacheHash) return;

    _dotsCacheHash = h;
    _dotsByDay = _buildDotsByDay(widget.schedules, widget.albas);
    if (mounted) setState(() {});
  }

  Map<DateTime, List<_DotEvent>> _buildDotsByDay(
    List<UICalendarSchedule> schedules,
    List<UICalendarAlba> albas,
  ) {
    final albaById = <String, UICalendarAlba>{
      for (final a in albas) a.id: a,
    };

    final map = <DateTime, Map<String, _DotEvent>>{};
    for (final s in schedules) {
      final key = DateTime(s.year, s.month, s.day);

      final alba = albaById[s.albaId] ??
          UICalendarAlba(
            id: s.albaId,
            storeId: '',
            name: '',
            colorHex: '#3B82F6',
            hourlyWage: 0,
            payDay: 25,
          );

      final fixedAlba = (alba.id.isEmpty)
          ? UICalendarAlba(
              id: s.albaId,
              storeId: '',
              name: '',
              colorHex: '#3B82F6',
              hourlyWage: 0,
              payDay: 25,
            )
          : alba;

      final bucket = (map[key] ??= <String, _DotEvent>{});
      bucket.putIfAbsent(
        fixedAlba.id,
        () => _DotEvent(cp.parseColor(fixedAlba.colorHex), fixedAlba.name),
      );
    }

    final out = <DateTime, List<_DotEvent>>{};
    for (final e in map.entries) {
      out[e.key] = e.value.values.take(4).toList();
    }
    return out;
  }

  Future<void> _safeDeleteSchedule(BuildContext ctx, String scheduleId) async {
    final sid = scheduleId.trim();
    if (sid.isEmpty) return;

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) {
        return AlertDialog(
          title: const Text(AppWords.delete),
          content: const Text('이 근무를 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text(AppWords.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(AppWords.delete),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await widget.onDeleteSchedule(sid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.done)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.failed}\n$e')),
      );
    }
  }

  Future<void> _confirmDeleteAlba(String albaId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: const Text(AppWords.delete),
          content: const Text(
            '알바 카드를 삭제하면 관련 근무 기록이 함께 정리될 수 있어요.\n계속할까요?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text(AppWords.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(AppWords.delete),
            ),
          ],
        );
      },
    );

    if (ok == true) widget.onDeleteAlba(albaId);
  }

  /// ✅ 핵심 수정: 바텀시트 닫힘(Barrier 제거) 이후 프레임에 이동
  Future<void> _showFabMenu() async {
    if (_joinSaving) return;

    final action = await showModalBottomSheet<_FabAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text(AppWords.joinByCode),
                  onTap: () => Navigator.pop(ctx, _FabAction.joinStore),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text(AppWords.addDirect),
                  onTap: () => Navigator.pop(ctx, _FabAction.addPersonal),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    // ✅ 여기서 “바로 push”하지 말고, 다음 프레임으로 넘겨 Barrier 잔류를 방지
    void go(VoidCallback fn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        fn();
      });
    }

    if (action == _FabAction.addPersonal) {
      go(widget.onGoToAlbaForm);
      return;
    }

    // join 플로우도 동일하게 안전하게
    go(() {
      _openJoinStoreFlow();
    });
  }

  Future<({String workerName, String? aliasName, bool inherit})?> _askJoinInfo(
    BuildContext context,
    String storeName,
  ) async {
    final nameCtrl = TextEditingController();
    final aliasCtrl = TextEditingController(text: storeName);
    bool inherit = true;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppWords.infoInput,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: AppWords.name,
                      hintText: AppWords.nameHint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: AppWords.storeAlias,
                      hintText: AppWords.storeAliasHint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: inherit,
                    onChanged: (v) => setState(() => inherit = v),
                    title: const Text(AppWords.inheritStoreSetting),
                    subtitle: Text(inherit ? AppWords.on : AppWords.off),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        final wn = nameCtrl.text.trim();
                        if (wn.isEmpty) return;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text(AppWords.next),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (ok != true) return null;

    final wn = nameCtrl.text.trim();
    final alias = aliasCtrl.text.trim();
    return (
      workerName: wn,
      aliasName: alias.isEmpty ? null : alias,
      inherit: inherit,
    );
  }

  Future<void> _openJoinStoreFlow() async {
    if (_joinSaving) return;

    final sheet = await showModalBottomSheet<JoinStoreSheetResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const JoinStoreSheet(),
    );

    if (!mounted || sheet == null) return;

    final joinInfo = await _askJoinInfo(context, sheet.initial.storeName);
    if (!mounted || joinInfo == null) return;

    final aliasName = joinInfo.aliasName ?? sheet.initial.storeName;
    final i0 = sheet.initial;
    final defaults = i0.storeDefaults;

    final initial = AlbaFormInitial(
      storeId: i0.storeId,
      storeName: aliasName,
      hourlyWage: i0.hourlyWage,
      tax: i0.tax,
      insurance: i0.insurance,
      surcharge: i0.surcharge,
      payrollPolicy: i0.payrollPolicy,
      startHour24: i0.startHour24,
      startMinute: i0.startMinute,
      endHour24: i0.endHour24,
      endMinute: i0.endMinute,
      breakMinutes: i0.breakMinutes,
      selectedDates: i0.selectedDates,
      colorHex: i0.colorHex,
      payDay: i0.payDay,
      inheritFromStore: joinInfo.inherit,
      storeDefaults: defaults,
    );

    final form = await Navigator.push<AlbaFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AlbaFormScreen(
          existingSchedules: widget.schedules,
          initial: initial,
          editingAlbaId: null,
          onBack: () => Navigator.pop(context),
          onSubmit: (r) => Navigator.pop(context, r),
        ),
      ),
    );

    if (!mounted || form == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.loginRequired)),
      );
      return;
    }

    if (widget.onJoinSubmit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.saveLinkRequired)),
      );
      return;
    }

    setState(() => _joinSaving = true);
    try {
      await widget.onJoinSubmit!(
        sheet,
        joinInfo.workerName,
        joinInfo.aliasName,
        form,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.done)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.failed}\n$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _joinSaving = false);
    }
  }

  void _onTapDay(DateTime selectedDay, DateTime focusedDay) async {
    setState(() => _selectedDay = selectedDay);

    final y = selectedDay.year, m = selectedDay.month, d = selectedDay.day;
    final localDate = DateTime(y, m, d);

    final groupedByAlba = <String, List<UICalendarSchedule>>{};
    for (final s in widget.schedules
        .where((s) => s.year == y && s.month == m && s.day == d)) {
      groupedByAlba.putIfAbsent(s.albaId, () => []).add(s);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cards = <Widget>[];

        for (final entry in groupedByAlba.entries) {
          final alba = widget.albas.firstWhere(
            (a) => a.id == entry.key,
            orElse: () => UICalendarAlba(
              id: entry.key,
              storeId: '',
              name: '',
              colorHex: '#3B82F6',
              hourlyWage: 0,
              payDay: 25,
            ),
          );
          final color = cp.parseColor(alba.colorHex);

          final list = [...entry.value]..sort((a, b) =>
              (a.startHour * 60 + a.startMinute)
                  .compareTo(b.startHour * 60 + b.startMinute));

          final merged = <_MergedBlock>[];
          for (final s in list) {
            if (merged.isEmpty) {
              merged.add(_MergedBlock.fromSingle(s));
            } else {
              final last = merged.last;
              if (last.isContiguousWith(s)) {
                last.absorb(s);
              } else {
                merged.add(_MergedBlock.fromSingle(s));
              }
            }
          }

          for (final block in merged) {
            cards.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: _ExpandableMergedCard(
                  alba: alba,
                  color: color,
                  block: block,
                  localDate: localDate,
                  onEdit: (scheduleId) {
                    Navigator.pop(ctx);
                    widget.onOpenWorkEditor(
                      wargs.WorkEditorArgs(
                        mode: wargs.WorkEditorArgsMode.edit,
                        scheduleId: scheduleId,
                        presetDate: localDate,
                        preselectedAlbaId: alba.id,
                      ),
                    );
                  },
                  onDelete: (scheduleId) async {
                    await _safeDeleteSchedule(ctx, scheduleId);
                    if (mounted && Navigator.of(ctx).canPop())
                      Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }
        }

        if (cards.isEmpty) {
          cards.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Text(
                AppWords.noWork,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${localDate.year}.${localDate.month.toString().padLeft(2, '0')}.${localDate.day.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: AppWords.addWork,
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onOpenWorkEditor(
                            wargs.WorkEditorArgs(
                              mode: wargs.WorkEditorArgsMode.add,
                              presetDate: localDate,
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ...cards,
              ],
            ),
          ),
        );
      },
    );

    // ✅ 바텀시트 닫히면 선택 표시 제거(요구사항 #6)
    if (!mounted) return;
    setState(() => _selectedDay = null);
  }

  pol.TaxConfig _taxOf(String id) =>
      (widget.getTaxPolicy?.call(id) as pol.TaxConfig?) ?? pol.TaxConfig.none;

  pol.InsuranceConfig _insOf(String id) =>
      (widget.getInsurancePolicy?.call(id) as pol.InsuranceConfig?) ??
      const pol.InsuranceNone();

  pol.SurchargePolicy? _surOf(String id) =>
      (widget.getSurchargePolicy?.call(id) as pol.SurchargePolicy?);

  PayrollPolicy? _payrollOf(String id) => widget.getPayrollPolicy?.call(id);

  bool _anySurchargeEnabled(pol.SurchargePolicy? s) {
    if (s == null) return false;
    return s.weeklyHolidayEnabled ||
        s.overtimeEnabled ||
        s.holidayEnabled ||
        s.nightEnabled;
  }

  String _labelTax(pol.TaxConfig t) {
    if (t == pol.TaxConfig.none) return AppWords.none;
    if (t == pol.TaxConfig.biz33) return '3.3%';
    if (t == pol.TaxConfig.day66) return '6.6%';
    if (t is pol.TaxConfigCustomPercent) return '${_trimPct(t.percent)}%';
    return AppWords.tax;
  }

  String _labelIns(pol.InsuranceConfig i) {
    if (i is pol.InsuranceNone) return AppWords.none;
    if (i is pol.InsuranceEmploymentOnly)
      return AppWords.insuranceEmploymentShort;
    if (i is pol.InsuranceFour) return AppWords.insuranceFourShort;
    return AppWords.insurance;
  }

  String _labelSurcharge(pol.SurchargePolicy? s) {
    if (!_anySurchargeEnabled(s)) return AppWords.none;
    final list = <String>[];
    if (s!.weeklyHolidayEnabled) list.add(AppWords.weeklyHoliday);
    if (s.overtimeEnabled) list.add(AppWords.workTypeOvertime);
    if (s.holidayEnabled) list.add(AppWords.workTypeHoliday);
    if (s.nightEnabled) list.add(AppWords.workTypeNight);
    return list.join(', ');
  }

  String _payrollSummaryLine(PayrollPolicy? p) {
    if (p == null) return AppWords.none;

    String cycleLabel() {
      switch (p.cycle) {
        case PayCycleType.monthly:
          return AppWords.payCycleMonthly;
        case PayCycleType.weekly:
          return AppWords.payCycleWeekly;
        case PayCycleType.twoWeeks:
          return AppWords.payCycleTwoWeeks;
        case PayCycleType.daily:
          return AppWords.payCycleDaily;
        case PayCycleType.customDays:
          return '${p.customEveryDays ?? 0}${AppWords.dayUnit}';
      }
    }

    String payRuleLabel() {
      switch (p.payRule.type) {
        case PayDateRuleType.nextMonthlyDay:
          return '${AppWords.payRuleMonthlyPrefix} ${p.payRule.monthlyDay ?? 15}${AppWords.dayUnit}';
        case PayDateRuleType.samePeriodEndDay:
          return AppWords.payRuleEndDay;
        case PayDateRuleType.afterEndPlusDays:
          return '${AppWords.payRuleEndPlusPrefix}${p.payRule.plusDays ?? 0}${AppWords.dayUnit}';
        case PayDateRuleType.fixedDate:
          return AppWords.payRuleFixed;
      }
    }

    return '${cycleLabel()} · ${payRuleLabel()}';
  }

  double _calcGrossUntilToday(
      UICalendarAlba alba, List<UICalendarSchedule> all) {
    final now = DateTime.now();
    final targets = all.where((s) {
      if (s.albaId != alba.id) return false;
      final d = DateTime(s.year, s.month, s.day);
      return !d.isAfter(DateTime(now.year, now.month, now.day));
    });

    double gross = 0;
    for (final s in targets) {
      final minutes = _workedMinutes(s);
      final wage = (s.overrideHourlyWage ?? alba.hourlyWage).toDouble();
      gross += (minutes / 60.0) * wage;
    }
    return gross;
  }

  int _workedMinutes(UICalendarSchedule s) {
    final start = Duration(hours: s.startHour, minutes: s.startMinute);
    var end = Duration(hours: s.endHour, minutes: s.endMinute);
    var diff = end - start;
    if (diff.isNegative) diff += const Duration(days: 1);
    final worked = diff.inMinutes - (s.breakMinutes).clamp(0, diff.inMinutes);
    return worked.clamp(0, 24 * 60);
  }

  int _totalWorkDaysOfMonth(String albaId) {
    final y = _focusedDay.year;
    final m = _focusedDay.month;
    return widget.schedules
        .where((s) => s.albaId == albaId && s.year == y && s.month == m)
        .length;
  }

  String _won(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return '$b원';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'PayMoa',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: widget.onBack,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _joinSaving ? null : _showFabMenu,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 3,
        icon: _joinSaving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(
          _joinSaving ? '처리 중…' : '추가',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: _WeeklyCalendarBox(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              onDaySelected: _onTapDay,
              onPageChanged: (fd) => setState(() => _focusedDay = fd),
              eventLoader: (day) {
                final k = DateTime(day.year, day.month, day.day);
                return _dotsByDay[k] ?? const <_DotEvent>[];
              },
            ),
          ),
          Expanded(
            child: widget.albas.isEmpty
                ? const _EmptyView()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: widget.albas.length,
                    itemBuilder: (context, index) {
                      final alba = widget.albas[index];
                      final color = cp.parseColor(alba.colorHex);
                      final todayGross =
                          _calcGrossUntilToday(alba, widget.schedules);

                      final tax = _taxOf(alba.id);
                      final ins = _insOf(alba.id);
                      final sur = _surOf(alba.id);
                      final payroll = _payrollOf(alba.id);

                      final rows = <Widget>[];
                      if (tax != pol.TaxConfig.none) {
                        rows.add(_kv(AppWords.tax, _labelTax(tax)));
                      }
                      if (ins is! pol.InsuranceNone) {
                        rows.add(_kv(AppWords.insurance, _labelIns(ins)));
                      }
                      if (_anySurchargeEnabled(sur)) {
                        rows.add(_kv(AppWords.surcharge, _labelSurcharge(sur)));
                      }
                      if (payroll != null) {
                        rows.add(_kv(
                            AppWords.payroll, _payrollSummaryLine(payroll)));
                      }

                      rows.add(
                        _kv(
                          '${_focusedDay.month}${AppWords.monthUnit} ${AppWords.workCount}',
                          '${_totalWorkDaysOfMonth(alba.id)}${AppWords.timesUnit}',
                        ),
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: _TossCard(
                          accent: color,
                          child: Theme(
                            data: theme.copyWith(
                                dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: PageStorageKey(alba.id),
                              tilePadding:
                                  const EdgeInsets.fromLTRB(0, 2, 0, 2),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(0, 10, 0, 12),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${alba.name}  ·  ${alba.payDay}${AppWords.dayUnit}',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${AppWords.hourlyWage}  ${_won(alba.hourlyWage)}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.68),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '예상 급여  ${_won(todayGross)}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.68),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: AppWords.delete,
                                      onPressed: () =>
                                          _confirmDeleteAlba(alba.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      onPressed: () =>
                                          widget.onEditAlba(alba.id),
                                      child: const Text(AppWords.edit),
                                    ),
                                    const Spacer(),
                                    FilledButton.tonal(
                                      onPressed: () => widget.onOpenWorkEditor(
                                        wargs.WorkEditorArgs(
                                          mode: wargs.WorkEditorArgsMode.add,
                                          preselectedAlbaId: alba.id,
                                        ),
                                      ),
                                      child: const Text(AppWords.addWork),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...rows,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _FabAction { joinStore, addPersonal }

/* ───────────────────────── 주간 달력 박스 ───────────────────────── */

class _WeeklyCalendarBox extends StatelessWidget {
  const _WeeklyCalendarBox({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.eventLoader,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final List<dynamic> Function(DateTime day) eventLoader;

  String _dowLabel(DateTime day) {
    switch (day.weekday) {
      case DateTime.sunday:
        return '일';
      case DateTime.monday:
        return '월';
      case DateTime.tuesday:
        return '화';
      case DateTime.wednesday:
        return '수';
      case DateTime.thursday:
        return '목';
      case DateTime.friday:
        return '금';
      case DateTime.saturday:
        return '토';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
      child: TableCalendar(
        locale: 'ko_KR',
        firstDay: DateTime.utc(2010, 1, 1),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: focusedDay,
        calendarFormat: CalendarFormat.week,
        availableCalendarFormats: const {CalendarFormat.week: 'Week'},
        startingDayOfWeek: StartingDayOfWeek.sunday,
        headerVisible: false,
        daysOfWeekVisible: true,
        daysOfWeekHeight: 26,
        selectedDayPredicate: (d) => isSameDay(selectedDay, d),
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        eventLoader: eventLoader,
        calendarBuilders: CalendarBuilders(
          dowBuilder: (ctx, day) {
            final label = _dowLabel(day);
            final isSun = day.weekday == DateTime.sunday;
            final isSat = day.weekday == DateTime.saturday;

            // ✅ 요일 색도 살짝 톤다운(쨍한 느낌 줄이기)
            final color = isSun
                ? Colors.redAccent.withOpacity(0.75)
                : isSat
                    ? Colors.blueAccent.withOpacity(0.75)
                    : theme.colorScheme.onSurface.withOpacity(0.55);

            return Center(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
          defaultBuilder: (ctx, day, _) => _DayCell(
            text: '${day.day}',
            selected: false,
            isToday: false,
          ),
          todayBuilder: (ctx, day, _) => _DayCell(
            text: '${day.day}',
            selected: false,
            isToday: true,
          ),
          selectedBuilder: (ctx, day, _) => _DayCell(
            text: '${day.day}',
            selected: true,
            isToday: false,
          ),
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            final dots = events.whereType<_DotEvent>().toList();
            if (dots.isEmpty) return const SizedBox.shrink();

            const double size = 6;
            const double gap = 4;

            return Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(dots.length.clamp(0, 4), (i) {
                  return Container(
                    width: size,
                    height: size,
                    margin: EdgeInsets.only(
                      right: i == dots.length - 1 ? 0 : gap,
                    ),
                    decoration: BoxDecoration(
                      color: dots[i].color,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            );
          },
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: true,
          isTodayHighlighted: false,
          markersMaxCount: 4,
          defaultTextStyle: theme.textTheme.bodyMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withOpacity(0.85),
          ),
          weekendTextStyle: theme.textTheme.bodyMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withOpacity(0.85),
          ),
          outsideTextStyle: theme.textTheme.bodyMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withOpacity(0.25),
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────── 기타 UI ───────────────────────── */

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          v,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              AppWords.emptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppWords.emptyHelp,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
