// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

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

Color _parseColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h, radix: 16) ?? 0x3B82F6;
  return Color(0xFF000000 | v);
}

String _workTypeLabel(WorkType t) {
  switch (t) {
    case WorkType.basic: return '기본근무';
    case WorkType.substitute: return '대타근무';
    case WorkType.overtime: return '연장근무';
    case WorkType.holiday: return '휴일근무';
    case WorkType.night: return '야간근무';
    case WorkType.weekly: return '주휴수당';
  }
}

/// TableCalendar에 뿌릴 이벤트 래퍼
class _MarkerEvent {
  final UICalendarSchedule s;
  final UICalendarAlba alba;
  _MarkerEvent(this.s, this.alba);
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
    this.wageAt,
  });

  final VoidCallback onBack;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;

  final void Function(String) onDeleteSchedule;
  final TaxConfig? Function(String albaId) getTaxPolicy;
  final InsuranceConfig? Function(String albaId) getInsurancePolicy;
  final SurchargePolicy? Function(String albaId) getSurchargePolicy;

  final void Function(wargs.WorkEditorArgs) openWorkEditor;

  /// (선택) 날짜별 시급 조회: (albaId, localDate) -> wage
  final int Function(String albaId, DateTime dateLocal)? wageAt;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now(); // 현재 보이는 달
  Set<String> activeIds = {}; // 표시 중인 알바(필터칩)

  @override
  void initState() {
    super.initState();
    activeIds = widget.albas.map((a) => a.id).toSet();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentAll = widget.albas.map((a) => a.id).toSet();
    activeIds.removeWhere((id) => !currentAll.contains(id));
    for (final id in currentAll) {
      if (!activeIds.contains(id)) activeIds.add(id);
    }
    setState(() {});
  }

  UICalendarAlba _albaByIdOrDefault(String id) {
    return widget.albas.firstWhere(
      (a) => a.id == id,
      orElse: () =>
          UICalendarAlba(id: id, name: '', colorHex: '#3B82F6', hourlyWage: 0),
    );
  }

  List<_MarkerEvent> _eventsOf(DateTime day) {
    final y = day.year, m = day.month, d = day.day;
    final list = widget.schedules
        .where((s) =>
            s.year == y &&
            s.month == m &&
            s.day == d &&
            activeIds.contains(s.albaId))
        .map((s) => _MarkerEvent(s, _albaByIdOrDefault(s.albaId)))
        .toList()
      ..sort((a, b) => (a.s.startHour * 60 + a.s.startMinute)
          .compareTo(b.s.startHour * 60 + b.s.startMinute));
    return list;
  }

  // ───────────────── 바텀시트: 날짜 상세 ─────────────────
  void _onTapDay(DateTime day, List<_MarkerEvent> events) {
    final localDate = DateTime(day.year, day.month, day.day);
    showModalBottomSheet<void>(
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
          final color = _parseColor(alba.colorHex);
          final schedules = [...entry.value]
            ..sort((a, b) => (a.startHour * 60 + a.startMinute)
                .compareTo(b.startHour * 60 + b.startMinute));

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

          // 🔵 중복 헤더 제거: 매장명/색상 Row 추가하지 않고 카드만 추가
          for (final block in merged) {
            final minutes = block.totalWorkedMinutes;
            final wagePerHour = widget.wageAt?.call(alba.id, localDate) ?? alba.hourlyWage;
            final basePay = (wagePerHour * minutes) ~/ 60;

            albaCards.add(
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: color, width: 3)),
                ),
                child: _ExpandableMergedCard(
                  alba: alba,
                  color: color,
                  block: block,
                  localDate: localDate,
                  basePay: basePay,
                  onEdit: (scheduleId) {
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
                  onDelete: (scheduleId) {
                    widget.onDeleteSchedule(scheduleId);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }
        }

        if (albaCards.isEmpty) {
          albaCards.add(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('선택한 날짜에 근무가 없습니다.'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.openWorkEditor(
                        wargs.WorkEditorArgs(mode: wargs.WorkEditorArgsMode.add, presetDate: localDate),
                      );
                    },
                    child: const Text('근무 추가'),
                  ),
                ],
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
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '근무 추가',
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.openWorkEditor(
                            wargs.WorkEditorArgs(mode: wargs.WorkEditorArgsMode.add, presetDate: localDate),
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ...albaCards,
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int netSum = 0;
    for (final aid in activeIds) {
      final alba = _albaByIdOrDefault(aid);
      final tax = widget.getTaxPolicy(aid) ?? TaxConfig.none;
      final ins = widget.getInsurancePolicy(aid) ?? const InsuranceNone();
      final pol = widget.getSurchargePolicy(aid) ?? const SurchargePolicy();

      final monthSchedules = widget.schedules
          .where((s) => s.albaId == aid && s.year == _focusedDay.year && s.month == _focusedDay.month)
          .toList();

      final summary = computeMonthlySummary(
        alba: alba,
        ymYear: _focusedDay.year,
        ymMonth: _focusedDay.month,
        schedules: monthSchedules,
        tax: tax,
        insurance: ins,
        policy: pol,
        wageAt: widget.wageAt,
      );
      netSum += summary.net;
    }

    final theme = Theme.of(context);
    final gridBorder = BorderSide(color: Colors.black.withOpacity(0.06), width: 1);

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '이전 달',
                  onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_focusedDay.year}년 ${_focusedDay.month}월',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '다음 달',
                  onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Text('급여:'),
                const SizedBox(width: 8),
                Text('${_comma(netSum)}원', style: theme.textTheme.titleMedium),
              ],
            ),
          ),

          if (widget.albas.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: widget.albas.map((a) {
                  final on = activeIds.contains(a.id);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(a.name),
                      selected: on,
                      selectedColor: _parseColor(a.colorHex).withOpacity(0.20),
                      onSelected: (_) {
                        setState(() {
                          if (on) {
                            activeIds.remove(a.id);
                          } else {
                            activeIds.add(a.id);
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          if (widget.albas.isNotEmpty) const SizedBox(height: 8),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TableCalendar<_MarkerEvent>(
                locale: 'ko_KR',
                firstDay: DateTime.utc(2010, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                headerVisible: false,
                startingDayOfWeek: StartingDayOfWeek.sunday,
                calendarFormat: CalendarFormat.month,
                availableGestures: AvailableGestures.horizontalSwipe,
                shouldFillViewport: true,
                daysOfWeekHeight: 32,
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: true,
                  isTodayHighlighted: true,
                  tablePadding: EdgeInsets.zero,
                ),
                eventLoader: (day) => _eventsOf(day),
                calendarBuilders: CalendarBuilders<_MarkerEvent>(
                  dowBuilder: (ctx, day) {
                    const labels = ['일', '월', '화', '수', '목', '금', '토'];
                    final idx = day.weekday % 7;
                    final isSun = idx == 0;
                    final isSat = idx == 6;
                    return Center(
                      child: Text(
                        labels[idx],
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSun
                              ? Colors.redAccent
                              : isSat
                                  ? Colors.blueAccent
                                  : theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    );
                  },
                  defaultBuilder: (ctx, day, _) {
                    final isSun = day.weekday == DateTime.sunday;
                    final isSat = day.weekday == DateTime.saturday;
                    final color = isSun
                        ? Colors.redAccent
                        : isSat
                            ? Colors.blueAccent
                            : theme.colorScheme.onSurface;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: gridBorder,
                          right: gridBorder,
                          bottom: gridBorder,
                        ),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(top: 6, left: 6, right: 4, bottom: 4),
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    );
                  },
                  todayBuilder: (ctx, day, _) {
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: gridBorder,
                          right: gridBorder,
                          bottom: gridBorder,
                        ),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(top: 6, left: 6, right: 4, bottom: 4),
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.green,
                        ),
                      ),
                    );
                  },
                  outsideBuilder: (ctx, day, _) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.02),
                        border: Border(
                          left: gridBorder,
                          right: gridBorder,
                          bottom: gridBorder,
                        ),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(top: 6, left: 6, right: 4, bottom: 4),
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ),
                    );
                  },

                  // ───────── 마커(칩) 병합 표시 ─────────
                  markerBuilder: (ctx, day, events) {
                    if (events.isEmpty) return const SizedBox.shrink();
                    final evs = events.cast<_MarkerEvent>();

                    // 1) 알바별로 모으기
                    final byAlba = <String, List<UICalendarSchedule>>{};
                    for (final e in evs) {
                      byAlba.putIfAbsent(e.alba.id, () => []).add(e.s);
                    }

                    // 2) 알바별로 "연속" 구간 병합 → 그날의 '칩' 1개로 축약
                    final merged = <MapEntry<UICalendarAlba, int>>[];
                    for (final entry in byAlba.entries) {
                      final alba = _albaByIdOrDefault(entry.key);
                      final list = [...entry.value]
                        ..sort((a, b) => (a.startHour * 60 + a.startMinute)
                            .compareTo(b.startHour * 60 + b.startMinute));

                      int start = list.first.startHour * 60 + list.first.startMinute;
                      int end = list.first.endHour * 60 + list.first.endMinute;
                      int breakSum = list.first.breakMinutes;

                      for (int i = 1; i < list.length; i++) {
                        final s = list[i];
                        final sMin = s.startHour * 60 + s.startMinute;
                        final eMin = s.endHour * 60 + s.endMinute;

                        if (sMin == end) {
                          end = eMin;
                          breakSum += s.breakMinutes;
                        } else {
                          final worked = ((end <= start ? end + 24 * 60 : end) - start) - breakSum;
                          merged.add(MapEntry(alba, worked.clamp(0, 24 * 60)));
                          start = sMin;
                          end = eMin;
                          breakSum = s.breakMinutes;
                        }
                      }
                      final worked = ((end <= start ? end + 24 * 60 : end) - start) - breakSum;
                      merged.add(MapEntry(alba, worked.clamp(0, 24 * 60)));
                    }

                    // 3) 칩 2개까지, 나머지는 +N
                    final chips = <Widget>[];
                    for (final ent in merged.take(2)) {
                      final color = _parseColor(ent.key.colorHex);
                      final onColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
                      chips.add(
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ent.key.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: onColor, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              Text(_hoursText(ent.value), style: TextStyle(color: onColor, fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    }
                    if (merged.length > 2) {
                      chips.add(
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '+${merged.length - 2}',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(top: 20, left: 4, right: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: chips,
                      ),
                    );
                  },
                ),
                onDaySelected: (selectedDay, focusedDay) {
                  _onTapDay(selectedDay, _eventsOf(selectedDay));
                  setState(() => _focusedDay = focusedDay);
                },
                onPageChanged: (fd) => setState(() => _focusedDay = fd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── 병합 블록/카드 위젯 ───────────────────────── */

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
    if (s.albaId != albaId || s.year != year || s.month != month || s.day != day) return false;
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
    required this.basePay,
    required this.onEdit,
    required this.onDelete,
  });

  final UICalendarAlba alba;
  final Color color;
  final _MergedBlock block;
  final DateTime localDate;
  final int basePay;
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
    final color = widget.color;

    final rangeText = _timeRangeText(b.startHour, b.startMinute, b.endHour, b.endMinute);
    final minutes = b.totalWorkedMinutes;
    final infoText = '${_hoursText(minutes)} · ${_comma(widget.basePay)}원';

    // 근무유형 조합 라벨(정렬 후 +로 연결)
    final types = b.types.map(_workTypeLabel).toList()..sort();
    final typeLabel = types.join('+');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.alba.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeLabel, style: theme.textTheme.labelMedium),
                ),
              ],
            ),
            subtitle: Text('$rangeText · $infoText'),
            trailing: IconButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 1),
                  ...b.children.map((s) {
                    final st = _fmtHm(s.startHour, s.startMinute);
                    final et = _fmtHm(s.endHour, s.endMinute);
                    final wt = _hoursText(_workedMinutes(s));
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      dense: true,
                      title: Text('${_workTypeLabel(s.workType)}  $st~$et  ($wt)'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(onPressed: () => widget.onEdit(s.id), child: const Text('편집')),
                          IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.onDelete(s.id),
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
