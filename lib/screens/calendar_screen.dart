// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../common/app_words.dart';
import '../common/common_pickers.dart' as cp;
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';
import '../payroll/payroll.dart';
import 'work_editor_args.dart' as wargs;

/* ───────────────────────── 공용 헬퍼 ───────────────────────── */

int _workedMinutes(UICalendarSchedule s) {
  final start = Duration(hours: s.startHour, minutes: s.startMinute);
  var end = Duration(hours: s.endHour, minutes: s.endMinute);
  var diff = end - start;
  if (diff.isNegative) diff += const Duration(days: 1);
  final worked = diff.inMinutes - (s.breakMinutes).clamp(0, diff.inMinutes);
  return worked.clamp(0, 24 * 60);
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
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && left % 3 == 0) buf.write(',');
  }
  return buf.toString();
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

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool _isSameMonth(DateTime a, int y, int m) => a.year == y && a.month == m;

/* ───────────────────────── Toss Tone UI (AlbaStartScreen 느낌) ───────────────────────── */

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

class _TightDayBubble extends StatelessWidget {
  const _TightDayBubble({
    required this.text,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
    required this.isSun,
    required this.isSat,
  });

  final String text;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;
  final bool isSun;
  final bool isSat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = isSelected
        ? theme.colorScheme.primaryContainer
        : isToday
            ? theme.colorScheme.primary.withOpacity(0.06)
            : Colors.transparent;

    // ✅ 일/토 날짜 색상 (선택 상태에서는 onPrimaryContainer 우선)
    Color base = theme.colorScheme.onSurface;
    if (isSun) base = Colors.redAccent;
    if (isSat) base = Colors.blueAccent;

    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : base.withOpacity(isOutside ? 0.35 : 0.90);

    final border = (!isSelected && isToday)
        ? Border.all(
            color: theme.colorScheme.primary.withOpacity(0.22),
            width: 1.1,
          )
        : null;

    return Container(
      width: 34,
      height: 34,
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
    );
  }
}

/* ───────────────────────── 내부 모델 ───────────────────────── */

class _MarkerEvent {
  final UICalendarSchedule s;
  final UICalendarAlba alba;
  _MarkerEvent(this.s, this.alba);
}

class _DayChip {
  final UICalendarAlba alba;
  final int workedMinutes;
  _DayChip(this.alba, this.workedMinutes);
}

class _PayMark {
  final String albaId;
  final String albaName;
  final Color color;
  final DateTime payDate; // dateOnly
  const _PayMark({
    required this.albaId,
    required this.albaName,
    required this.color,
    required this.payDate,
  });
}

/* ───────────────────────── 화면 ───────────────────────── */

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.onBack,
    required this.albas,
    required this.schedules,
    required this.onDeleteSchedule,
    required this.getTaxPolicy,
    required this.getInsurancePolicy,
    required this.getSurchargePolicy,
    required this.openWorkEditor,
    this.getPayrollPolicy,
    this.wageAt,
    this.readOnly = false,
  });

  final VoidCallback onBack;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;

  final Future<void> Function(String) onDeleteSchedule;

  final TaxConfig? Function(String albaId) getTaxPolicy;
  final InsuranceConfig? Function(String albaId) getInsurancePolicy;
  final SurchargePolicy? Function(String albaId) getSurchargePolicy;

  final void Function(wargs.WorkEditorArgs) openWorkEditor;

  final PayrollPolicy? Function(String albaId)? getPayrollPolicy;
  final int Function(String albaId, DateTime dateLocal)? wageAt;

  final bool readOnly;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<String> activeIds = {};

  Map<String, UICalendarAlba> _albaMap = const {};
  Map<DateTime, List<_MarkerEvent>> _eventsByDay = const {};
  Map<DateTime, List<_DayChip>> _chipsByDay = const {};
  int _cacheHash = 0;

  int _payHash = 0;
  String _payYmKey = '';
  Map<DateTime, List<_PayMark>> _payByDay = const {};

  @override
  void initState() {
    super.initState();
    activeIds = widget.albas.map((a) => a.id).toSet();
    _rebuildCaches(force: true);
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currentAll = widget.albas.map((a) => a.id).toSet();
    activeIds.removeWhere((id) => !currentAll.contains(id));
    for (final id in currentAll) {
      activeIds.add(id);
    }

    _rebuildCaches();
  }

  int _calcCacheHash() {
    return Object.hash(
      widget.albas.length,
      Object.hashAll(widget.albas.map((a) => a.id)),
      widget.schedules.length,
      Object.hashAll(widget.schedules.map((s) => s.id)),
    );
  }

  void _rebuildCaches({bool force = false}) {
    final h = _calcCacheHash();
    if (!force && h == _cacheHash) return;
    _cacheHash = h;

    final am = <String, UICalendarAlba>{};
    for (final a in widget.albas) {
      am[a.id] = a;
    }
    _albaMap = am;

    final eb = <DateTime, List<_MarkerEvent>>{};
    for (final s in widget.schedules) {
      final alba = _albaMap[s.albaId] ?? _fallbackAlba(s.albaId);
      final k = _dayKey(DateTime(s.year, s.month, s.day));
      (eb[k] ??= <_MarkerEvent>[]).add(_MarkerEvent(s, alba));
    }

    for (final k in eb.keys) {
      eb[k]!.sort((a, b) {
        final amn = a.s.startHour * 60 + a.s.startMinute;
        final bmn = b.s.startHour * 60 + b.s.startMinute;
        if (amn != bmn) return amn.compareTo(bmn);
        return a.s.id.compareTo(b.s.id);
      });
    }
    _eventsByDay = eb;

    final cb = <DateTime, List<_DayChip>>{};
    for (final entry in eb.entries) {
      final byAlba = <String, int>{};
      for (final ev in entry.value) {
        final minutes = _workedMinutes(ev.s);
        byAlba.update(ev.alba.id, (v) => v + minutes, ifAbsent: () => minutes);
      }

      final chips = byAlba.entries
          .map(
            (e) => _DayChip(
              _albaMap[e.key] ?? _fallbackAlba(e.key),
              e.value,
            ),
          )
          .toList();

      chips.sort((a, b) {
        final c = b.workedMinutes.compareTo(a.workedMinutes);
        if (c != 0) return c;
        return a.alba.name.compareTo(b.alba.name);
      });

      cb[entry.key] = chips;
    }
    _chipsByDay = cb;

    _payYmKey = '';
    _payByDay = const {};

    if (mounted) setState(() {});
  }

  UICalendarAlba _fallbackAlba(String id) {
    return UICalendarAlba(
      id: id,
      name: '',
      colorHex: '#3B82F6',
      hourlyWage: 0,
      payDay: 25,
    );
  }

  List<_MarkerEvent> _eventsOf(DateTime day) {
    final k = _dayKey(day);
    final list = _eventsByDay[k] ?? const <_MarkerEvent>[];
    if (list.isEmpty) return const <_MarkerEvent>[];

    if (activeIds.length == widget.albas.length) return list;

    final filtered = <_MarkerEvent>[];
    for (final e in list) {
      if (activeIds.contains(e.alba.id)) filtered.add(e);
    }
    return filtered;
  }

  List<_DayChip> _chipsOf(DateTime day) {
    final k = _dayKey(day);
    final list = _chipsByDay[k] ?? const <_DayChip>[];
    if (list.isEmpty) return const <_DayChip>[];

    if (activeIds.length == widget.albas.length) return list;

    final filtered = <_DayChip>[];
    for (final c in list) {
      if (activeIds.contains(c.alba.id)) filtered.add(c);
    }
    return filtered;
  }

  UICalendarAlba _albaByIdOrDefault(String id) =>
      _albaMap[id] ?? _fallbackAlba(id);

  // ───────────────────────── 급여일 계산 ─────────────────────────

  Map<DateTime, List<_PayMark>> _buildPayMarksForMonth(int y, int m) {
    final getter = widget.getPayrollPolicy;
    if (getter == null) return const {};

    final ymKey = '$y-$m';
    final h = Object.hash(_cacheHash, ymKey, Object.hashAll(activeIds));
    if (_payYmKey == ymKey && _payHash == h) return _payByDay;

    _payYmKey = ymKey;
    _payHash = h;

    final prevMonth = (m == 1) ? DateTime(y - 1, 12, 1) : DateTime(y, m - 1, 1);
    final afterNext = (m == 11)
        ? DateTime(y + 1, 1, 1)
        : (m == 12)
            ? DateTime(y + 1, 2, 1)
            : DateTime(y, m + 2, 1);

    final rangeStart = prevMonth;
    final rangeEndExclusive = afterNext;

    final map = <DateTime, List<_PayMark>>{};

    for (final aid in activeIds) {
      final alba = _albaByIdOrDefault(aid);
      final color = cp.parseColor(alba.colorHex);

      final policy = getter(aid);
      if (policy == null) continue;

      final workedDays = <DateTime>{};
      for (final s in widget.schedules) {
        if (s.albaId != aid) continue;
        final d = DateTime(s.year, s.month, s.day);
        if (d.isBefore(rangeStart) || !d.isBefore(rangeEndExclusive)) continue;
        workedDays.add(_dateOnly(d));
      }
      if (workedDays.isEmpty) continue;

      final periods = <String, PeriodPayPreview>{};
      for (final d in workedDays) {
        final preview =
            computePreviewForDate(policy: policy, anyDateInPeriod: d);
        final k =
            '${preview.period.start.toIso8601String()}|${preview.period.end.toIso8601String()}';
        periods.putIfAbsent(k, () => preview);
      }

      for (final p in periods.values) {
        final pay = _dateOnly(p.payDate);
        if (!_isSameMonth(pay, y, m)) continue;

        (map[pay] ??= <_PayMark>[]).add(
          _PayMark(
            albaId: aid,
            albaName: alba.name,
            color: color,
            payDate: pay,
          ),
        );
      }
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) => a.albaName.compareTo(b.albaName));
    }

    _payByDay = map;
    return map;
  }

  List<_PayMark> _payMarksOfDay(DateTime day) {
    final m = _buildPayMarksForMonth(_focusedDay.year, _focusedDay.month);
    return m[_dateOnly(day)] ?? const <_PayMark>[];
  }

  // ───────────────────────── 삭제 확인 ─────────────────────────

  Future<void> _safeDeleteSchedule(BuildContext ctx, String scheduleId) async {
    if (widget.readOnly) return;

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

  // ───────────────────────── 바텀시트 ─────────────────────────

  Future<void> _onTapDay(DateTime day, List<_MarkerEvent> events) async {
    final localDate = DateTime(day.year, day.month, day.day);
    final payMarks = _payMarksOfDay(day);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        final groupedByAlba = <String, List<UICalendarSchedule>>{};
        for (final ev in events) {
          groupedByAlba.putIfAbsent(ev.alba.id, () => []).add(ev.s);
        }

        final albaCards = <Widget>[];
        for (final entry in groupedByAlba.entries) {
          final alba = _albaByIdOrDefault(entry.key);
          final color = cp.parseColor(alba.colorHex);

          final schedules = [...entry.value]..sort((a, b) {
              final amn = a.startHour * 60 + a.startMinute;
              final bmn = b.startHour * 60 + b.startMinute;
              if (amn != bmn) return amn.compareTo(bmn);
              return a.id.compareTo(b.id);
            });

          final merged = <_MergedBlock>[];
          for (final s in schedules) {
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
            albaCards.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: _TossAccentCard(
                  accent: color,
                  child: _ExpandableMergedCard(
                    alba: alba,
                    color: color,
                    block: block,
                    localDate: localDate,
                    readOnly: widget.readOnly,
                    onEdit: (scheduleId) {
                      if (widget.readOnly) return;
                      Navigator.pop(ctx);
                      widget.openWorkEditor(
                        wargs.WorkEditorArgs(
                          mode: wargs.WorkEditorArgsMode.edit,
                          scheduleId: scheduleId,
                          presetDate: localDate,
                          preselectedAlbaId: alba.id,
                        ),
                      );
                    },
                    onDelete: (scheduleId) async {
                      if (widget.readOnly) return;
                      await _safeDeleteSchedule(ctx, scheduleId);
                      if (mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
            );
          }
        }

        if (albaCards.isEmpty) {
          albaCards.add(
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(AppWords.noWork),
            ),
          );
        }

        Widget payBadgeRow() {
          if (payMarks.isEmpty) return const SizedBox.shrink();

          final shown = payMarks.take(2).toList();
          final more = payMarks.length - shown.length;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final pm in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _PayBadge(color: pm.color),
                ),
              if (more > 0)
                Text(
                  '+$more',
                  style: theme.textTheme.bodySmall,
                ),
            ],
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
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 10),
                      payBadgeRow(),
                      const Spacer(),
                      if (!widget.readOnly)
                        IconButton(
                          tooltip: AppWords.addWork,
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.openWorkEditor(
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
                ...albaCards,
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────── 셀(스타일) ─────────────────────────

  Widget _dayCell(
    BuildContext ctx,
    DateTime day, {
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final payMarks = _payMarksOfDay(day);
    final chipsData = _chipsOf(day);

    final idx = day.weekday % 7; // Sunday=0 ... Saturday=6
    final isSun = idx == 0;
    final isSat = idx == 6;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _TightDayBubble(
                text: '${day.day}',
                isToday: isToday,
                isSelected: isSelected,
                isOutside: isOutside,
                isSun: isSun,
                isSat: isSat,
              ),
              Expanded(child: _InlinePayBadges(marks: payMarks)),
            ],
          ),

          // ✅ 근무 바를 "날짜 바로 아래"로
          if (chipsData.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Bars(chips: chipsData),
          ],

          const Spacer(),
        ],
      ),
    );
  }

  // ✅ 월별 rowHeight 계산: 화면 빈공간을 달력 셀이 먹도록
  int _weeksInMonthGrid(DateTime focusedDay) {
    final first = DateTime(focusedDay.year, focusedDay.month, 1);
    final firstWeekday = first.weekday % 7; // Sunday=0 ... Saturday=6
    final daysInMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
    return ((firstWeekday + daysInMonth) / 7.0).ceil();
  }

  @override
  Widget build(BuildContext context) {
    int netSum = 0;

    for (final aid in activeIds) {
      final alba = _albaByIdOrDefault(aid);
      final tax = widget.getTaxPolicy(aid) ?? TaxConfig.none;
      final ins = widget.getInsurancePolicy(aid) ?? const InsuranceNone();
      final polc = widget.getSurchargePolicy(aid) ?? const SurchargePolicy();

      final monthSchedules = widget.schedules
          .where((s) =>
              s.albaId == aid &&
              s.year == _focusedDay.year &&
              s.month == _focusedDay.month)
          .toList();

      final summary = computeMonthlySummary(
        alba: alba,
        ymYear: _focusedDay.year,
        ymMonth: _focusedDay.month,
        schedules: monthSchedules,
        tax: tax,
        insurance: ins,
        policy: polc,
        wageAt: widget.wageAt,
      );
      netSum += summary.net;
    }

    final theme = Theme.of(context);
    _buildPayMarksForMonth(_focusedDay.year, _focusedDay.month);

    final weeks = _weeksInMonthGrid(_focusedDay);
    const daysOfWeekHeight = 22.0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: widget.onBack,
        ),
        title: const Text(AppWords.calendar),
        centerTitle: true,
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: _TossCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: AppWords.prevMonth,
                          onPressed: () => setState(() => _focusedDay =
                              DateTime(
                                  _focusedDay.year, _focusedDay.month - 1, 1)),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '${_focusedDay.year}년 ${_focusedDay.month}월',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppWords.nextMonth,
                          onPressed: () => setState(() => _focusedDay =
                              DateTime(
                                  _focusedDay.year, _focusedDay.month + 1, 1)),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          AppWords.monthlyNetEstimate,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_comma(netSum)}원',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    if (widget.albas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: widget.albas.map((a) {
                            final on = activeIds.contains(a.id);
                            final c = cp.parseColor(a.colorHex);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(a.name),
                                selected: on,
                                selectedColor: c.withOpacity(0.18),
                                onSelected: (_) {
                                  setState(() {
                                    if (on) {
                                      activeIds.remove(a.id);
                                    } else {
                                      activeIds.add(a.id);
                                    }
                                    _payYmKey = '';
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: _TossCard(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: LayoutBuilder(
                    builder: (ctx, cons) {
                      final available =
                          (cons.maxHeight - daysOfWeekHeight).clamp(0.0, 99999);

                      final computedRowHeight =
                          (available / weeks).clamp(86.0, 140.0);

                      return TableCalendar<_MarkerEvent>(
                        locale: 'ko_KR',
                        firstDay: DateTime.utc(2010, 1, 1),
                        lastDay: DateTime.utc(2035, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                        headerVisible: false,
                        startingDayOfWeek: StartingDayOfWeek.sunday,
                        calendarFormat: CalendarFormat.month,
                        availableGestures: AvailableGestures.horizontalSwipe,
                        rowHeight: computedRowHeight,
                        daysOfWeekHeight: daysOfWeekHeight,
                        calendarStyle: const CalendarStyle(
                          outsideDaysVisible: true,
                          isTodayHighlighted: false,
                          tablePadding: EdgeInsets.zero,
                          cellMargin: EdgeInsets.zero,
                          cellPadding: EdgeInsets.zero,
                        ),
                        eventLoader: (day) => _eventsOf(day),
                        calendarBuilders: CalendarBuilders<_MarkerEvent>(
                          dowBuilder: (ctx, day) {
                            const labels = ['일', '월', '화', '수', '목', '금', '토'];
                            final idx = day.weekday % 7;
                            final isSun = idx == 0;
                            final isSat = idx == 6;

                            final Color color = isSun
                                ? Colors.redAccent.withOpacity(0.75)
                                : isSat
                                    ? Colors.blueAccent.withOpacity(0.75)
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.55);

                            // ✅ 날짜 셀과 동일 padding → X축 정렬 맞춤
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Center(
                                child: Text(
                                  labels[idx],
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: color,
                                  ),
                                ),
                              ),
                            );
                          },
                          defaultBuilder: (ctx, day, _) => _dayCell(
                            ctx,
                            day,
                            isToday: false,
                            isSelected: false,
                            isOutside: false,
                          ),
                          todayBuilder: (ctx, day, _) => _dayCell(
                            ctx,
                            day,
                            isToday: true,
                            isSelected: false,
                            isOutside: false,
                          ),
                          selectedBuilder: (ctx, day, _) => _dayCell(
                            ctx,
                            day,
                            isToday: false,
                            isSelected: true,
                            isOutside: false,
                          ),
                          outsideBuilder: (ctx, day, _) => _dayCell(
                            ctx,
                            day,
                            isToday: false,
                            isSelected: false,
                            isOutside: true,
                          ),
                          markerBuilder: (ctx, day, events) =>
                              const SizedBox.shrink(),
                        ),
                        onDaySelected: (selectedDay, focusedDay) async {
                          final ev = _eventsOf(selectedDay);

                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });

                          await _onTapDay(selectedDay, ev);

                          if (!mounted) return;
                          setState(() => _selectedDay = null);
                        },
                        onPageChanged: (fd) => setState(() {
                          _focusedDay = fd;
                          _selectedDay = null;
                        }),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ───────────────────────── 아래 위젯들(원본 유지) ───────────────────────── */

class _InlinePayBadges extends StatelessWidget {
  const _InlinePayBadges({required this.marks});
  final List<_PayMark> marks;

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) return const SizedBox.shrink();

    final shown = marks.take(2).toList();
    final more = marks.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        for (final m in shown)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _GupBadge(color: m.color),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+$more',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: 10),
            ),
          ),
      ],
    );
  }
}

class _GupBadge extends StatelessWidget {
  const _GupBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.3),
      ),
      child: Text(
        '급',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
            ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.chips});
  final List<_DayChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    final shown = chips.take(3).toList();
    final more = chips.length - shown.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in shown) _CalendarHourBar(c: c),
        if (more > 0) const _MoreDots(),
      ],
    );
  }
}

class _MoreDots extends StatelessWidget {
  const _MoreDots();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = theme.colorScheme.onSurface.withOpacity(0.38);

    Widget dot() => Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(),
          const SizedBox(width: 3),
          dot(),
          const SizedBox(width: 3),
          dot(),
        ],
      ),
    );
  }
}

class _CalendarHourBar extends StatelessWidget {
  const _CalendarHourBar({required this.c});
  final _DayChip c;

  @override
  Widget build(BuildContext context) {
    final color = cp.parseColor(c.alba.colorHex);
    final onColor =
        color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Container(
      height: 18,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          _hoursText(c.workedMinutes),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onColor,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PayBadge extends StatelessWidget {
  const _PayBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '급여일',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TossAccentCard extends StatelessWidget {
  const _TossAccentCard({
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

/* ───────────────────────── 병합 블록/카드 위젯(원본 유지) ───────────────────────── */

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
        s.day != day) {
      return false;
    }
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
    required this.readOnly,
  });

  final UICalendarAlba alba;
  final Color color;
  final _MergedBlock block;
  final DateTime localDate;

  final void Function(String scheduleId) onEdit;
  final void Function(String scheduleId) onDelete;

  final bool readOnly;

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

    return Column(
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
                Divider(height: 1, color: theme.dividerColor.withOpacity(0.35)),
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
                    trailing: widget.readOnly
                        ? null
                        : Row(
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
    );
  }
}
