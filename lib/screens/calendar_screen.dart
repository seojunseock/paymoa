// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';

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

/* ───────────────────────── Toss Tone UI ───────────────────────── */

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

  static const _primary = Color(0xFF7C3AED);
  static const _todayColor = Color(0xFF10B981);
  static const _sunColor = Color(0xFFE53935);
  static const _satColor = Color(0xFF1E88E5);
  static const _textPrimary = Color(0xFF111827);

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? _primary.withOpacity(0.85) : Colors.transparent;

    Color base = _textPrimary;
    if (isSun) base = _sunColor;
    if (isSat) base = _satColor;
    if (isToday && !isSelected) base = _todayColor;

    final fg = isSelected
        ? Colors.white
        : isOutside
            ? base.withOpacity(0.30)
            : base;

    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isToday
              ? FontWeight.w800
              : isSelected
                  ? FontWeight.w700
                  : FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

/* ───────────────────────── 요일 헤더 ───────────────────────── */

class _CalDowHeader extends StatelessWidget {
  const _CalDowHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    const colors = [
      Color(0xFFE53935),
      Color(0xFF9CA3AF),
      Color(0xFF9CA3AF),
      Color(0xFF9CA3AF),
      Color(0xFF9CA3AF),
      Color(0xFF9CA3AF),
      Color(0xFF1E88E5),
    ];
    return SizedBox(
      height: 28,
      child: Row(
        children: List.generate(
          7,
          (i) => Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors[i],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
  final DateTime payDate;
  final int net;
  final DateTime periodStart;
  final DateTime periodEnd;
  const _PayMark({
    required this.albaId,
    required this.albaName,
    required this.color,
    required this.payDate,
    required this.net,
    required this.periodStart,
    required this.periodEnd,
  });
}

class _JuhuMark {
  final String albaId;
  final String albaName;
  final Color color;
  final int juhuPay;
  const _JuhuMark({
    required this.albaId,
    required this.albaName,
    required this.color,
    required this.juhuPay,
  });
}

/* ───────────────────────── 화면 ───────────────────────── */

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.onBack,
    required this.albas,
    required this.schedules,
    required this.onDeleteSchedule,
    required this.getTaxPolicy,
    required this.getInsurancePolicy,
    required this.getSurchargePolicy,
    this.getSurchargeAt,
    this.getTaxAt,
    this.getInsuranceAt,
    required this.openWorkEditor,
    this.getPayrollPolicy,
    this.wageAt,
    this.readOnly = false,
  });

  final VoidCallback? onBack;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;

  final Future<void> Function(String) onDeleteSchedule;

  final TaxConfig? Function(String albaId) getTaxPolicy;
  final InsuranceConfig? Function(String albaId) getInsurancePolicy;
  final SurchargePolicy? Function(String albaId) getSurchargePolicy;
  final SurchargePolicy Function(DateTime)? Function(String albaId)?
      getSurchargeAt;
  final TaxConfig Function(DateTime)? Function(String albaId)? getTaxAt;
  final InsuranceConfig Function(DateTime)? Function(String albaId)?
      getInsuranceAt;

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

  int _juhuHash = 0;
  String _juhuYmKey = '';
  Map<DateTime, List<_JuhuMark>> _juhuByDay = const {};

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
    _juhuYmKey = '';
    _juhuByDay = const {};

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

      final tax = widget.getTaxPolicy(aid) ?? TaxConfig.none;
      final ins = widget.getInsurancePolicy(aid) ?? const InsuranceNone();
      final polc = widget.getSurchargePolicy(aid) ?? const SurchargePolicy();
      final surchargeAt = widget.getSurchargeAt?.call(aid);
      final taxAt = widget.getTaxAt?.call(aid);
      final insuranceAt = widget.getInsuranceAt?.call(aid);
      final albaSchedules =
          widget.schedules.where((s) => s.albaId == aid).toList();

      for (final p in periods.values) {
        final pay = _dateOnly(p.payDate);
        if (!_isSameMonth(pay, y, m)) continue;

        final summary = const PayrollEngine().summaryForDate(
          policy: policy,
          alba: alba,
          schedules: albaSchedules,
          tax: tax,
          insurance: ins,
          surchargePolicy: polc,
          wageAt: widget.wageAt,
          surchargeAt: surchargeAt,
          taxAt: taxAt,
          insuranceAt: insuranceAt,
          anyDateInPeriod: p.period.start,
        );

        (map[pay] ??= <_PayMark>[]).add(
          _PayMark(
            albaId: aid,
            albaName: alba.name,
            color: color,
            payDate: pay,
            net: summary.net,
            periodStart: _dateOnly(p.period.start),
            periodEnd: _dateOnly(p.period.end),
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

  Map<DateTime, List<_JuhuMark>> _buildJuhuMarksForMonth(int y, int m) {
    final ymKey = '$y-$m-juhu';
    final h = Object.hash(_cacheHash, ymKey, Object.hashAll(activeIds));
    if (_juhuYmKey == ymKey && _juhuHash == h) return _juhuByDay;

    _juhuYmKey = ymKey;
    _juhuHash = h;

    final map = <DateTime, List<_JuhuMark>>{};

    final monthStart = DateTime(y, m, 1);
    final monthEnd = DateTime(y, m + 1, 0);

    for (final aid in activeIds) {
      final sur = widget.getSurchargePolicy(aid);
      if (sur == null || !sur.weeklyHolidayEnabled) continue;

      final alba = _albaByIdOrDefault(aid);
      final color = cp.parseColor(alba.colorHex);

      final weeklyMinutes = <DateTime, int>{};
      final weeklyWorkDays = <DateTime, Set<String>>{};

      final rangeStart = monthStart.subtract(const Duration(days: 7));
      final rangeEnd = monthEnd.add(const Duration(days: 7));

      for (final s in widget.schedules) {
        if (s.albaId != aid) continue;
        if (s.workType != WorkType.basic) continue;

        final d = DateTime(s.year, s.month, s.day);
        if (d.isBefore(rangeStart) || d.isAfter(rangeEnd)) continue;

        final weekStart = d.subtract(Duration(days: d.weekday % 7)); // 일요일 시작
        final worked = _workedMinutes(s);
        weeklyMinutes[weekStart] = (weeklyMinutes[weekStart] ?? 0) + worked;
        (weeklyWorkDays[weekStart] ??= <String>{}).add(
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }

      for (final entry in weeklyMinutes.entries) {
        if (entry.value < 15 * 60) continue;

        final weekStart = entry.key;
        final holidayDate =
            _dateOnly(weekStart.add(const Duration(days: 6))); // 토요일 귀속

        if (!_isSameMonth(holidayDate, y, m)) continue;

        final paidMinutes = sur.weeklyHolidayUseFixedMinutes
            ? sur.weeklyHolidayFixedMinutes
            : (entry.value /
                    (weeklyWorkDays[weekStart]?.length == 0
                        ? 1
                        : weeklyWorkDays[weekStart]!.length))
                .round();

        final wage = widget.wageAt?.call(aid, holidayDate) ?? alba.hourlyWage;
        final juhuPay = (wage * (paidMinutes / 60.0)).round();

        (map[holidayDate] ??= <_JuhuMark>[]).add(
          _JuhuMark(
            albaId: aid,
            albaName: alba.name,
            color: color,
            juhuPay: juhuPay,
          ),
        );
      }
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) => a.albaName.compareTo(b.albaName));
    }

    _juhuByDay = map;
    return map;
  }

  List<_JuhuMark> _juhuMarksOfDay(DateTime day) {
    final m = _buildJuhuMarksForMonth(_focusedDay.year, _focusedDay.month);
    return m[_dateOnly(day)] ?? const <_JuhuMark>[];
  }

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
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(
                AppWords.delete,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF43F5E),
                ),
              ),
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
        const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _onTapDay(DateTime day, List<_MarkerEvent> events) async {
    final localDate = DateTime(day.year, day.month, day.day);
    final payMarks = _payMarksOfDay(day);
    final juhuMarks = _juhuMarksOfDay(day);

    if (events.isEmpty &&
        payMarks.isEmpty &&
        juhuMarks.isEmpty &&
        widget.readOnly) {
      return;
    }

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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: _TossAccentCard(
                  accent: color,
                  child: _ExpandableMergedCard(
                    alba: alba,
                    color: color,
                    block: block,
                    localDate: localDate,
                    readOnly: widget.readOnly,
                    wageAt: widget.wageAt,
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
                      final nav = Navigator.of(ctx);
                      await _safeDeleteSchedule(ctx, scheduleId);
                      if (!mounted) return;
                      if (nav.mounted) nav.pop();
                    },
                  ),
                ),
              ),
            );
          }
        }

        final juhuCards = <Widget>[
          for (final m in juhuMarks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: m.color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: m.color.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 36,
                      decoration: BoxDecoration(
                        color: m.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.albaName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '주휴수당',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: m.color.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+${_comma(m.juhuPay)}원',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: m.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];

        final payCards = <Widget>[
          for (final m in payMarks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: m.color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: m.color.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 44,
                      decoration: BoxDecoration(
                        color: m.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.albaName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${m.periodStart.month}/${m.periodStart.day}~${m.periodEnd.month}/${m.periodEnd.day} 급여일',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_comma(m.net)}원',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: m.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];

        final hasInfoCards = juhuCards.isNotEmpty || payCards.isNotEmpty;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    '${localDate.year}.${localDate.month.toString().padLeft(2, '0')}.${localDate.day.toString().padLeft(2, '0')}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (juhuCards.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                    child: const Text(
                      '주휴수당',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  ...juhuCards,
                ],
                if (payCards.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      juhuCards.isEmpty ? 4 : 10,
                      16,
                      2,
                    ),
                    child: const Text(
                      '급여',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  ...payCards,
                ],
                if (hasInfoCards && albaCards.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Divider(height: 1, color: Color(0xFFE5E7EB)),
                  ),
                if (albaCards.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      hasInfoCards ? 4 : 4,
                      16,
                      2,
                    ),
                    child: const Text(
                      '근무',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  ...albaCards,
                ],
                if (albaCards.isEmpty && !widget.readOnly)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      AppWords.noWork,
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    ),
                  ),
                if (!widget.readOnly) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.openWorkEditor(
                            wargs.WorkEditorArgs(
                              mode: wargs.WorkEditorArgsMode.add,
                              presetDate: localDate,
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text(
                          '근무 추가',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dayCell(
    BuildContext ctx,
    DateTime day, {
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final payMarks = _payMarksOfDay(day);
    final juhuMarks = _juhuMarksOfDay(day);
    final chipsData = _chipsOf(day);

    final idx = day.weekday % 7;
    final isSun = idx == 0;
    final isSat = idx == 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.topCenter,
          child: _TightDayBubble(
            text: '${day.day}',
            isToday: isToday,
            isSelected: isSelected,
            isOutside: isOutside,
            isSun: isSun,
            isSat: isSat,
          ),
        ),
        const SizedBox(height: 1),
        if (payMarks.isNotEmpty && !isOutside)
          Center(child: _InlinePayBadges(marks: payMarks)),
        if (juhuMarks.isNotEmpty && !isOutside)
          Center(child: _InlineJuhuBadges(marks: juhuMarks)),
        if (chipsData.isNotEmpty && !isOutside) _Bars(chips: chipsData),
      ],
    );
  }

  int _weeksInMonthGrid(DateTime focusedDay) {
    final first = DateTime(focusedDay.year, focusedDay.month, 1);
    final firstDow = first.weekday % 7;
    final daysInMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
    final natural = ((firstDow + daysInMonth) / 7.0).ceil();
    return natural < 5 ? 5 : natural;
  }

  DateTime _gridDayAt(int weekIdx, int dowIdx) {
    final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final firstDow = first.weekday % 7;
    final offset = weekIdx * 7 + dowIdx - firstDow;
    return first.add(Duration(days: offset));
  }

  @override
  Widget build(BuildContext context) {
    int netSum = 0;

    for (final aid in activeIds) {
      final alba = _albaByIdOrDefault(aid);
      final tax = widget.getTaxPolicy(aid) ?? TaxConfig.none;
      final ins = widget.getInsurancePolicy(aid) ?? const InsuranceNone();
      final polc = widget.getSurchargePolicy(aid) ?? const SurchargePolicy();
      final payroll = widget.getPayrollPolicy?.call(aid);
      final surchargeAt = widget.getSurchargeAt?.call(aid);
      final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);

      final isCalendarMonth = payroll == null ||
          (payroll.cycle == PayCycleType.monthly &&
              (payroll.monthlyStartDay ?? 1) == 1);

      if (isCalendarMonth) {
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
          tax: widget.getTaxAt?.call(aid)?.call(monthStart) ?? tax,
          insurance: widget.getInsuranceAt?.call(aid)?.call(monthStart) ?? ins,
          policy: polc,
          surchargeAt: surchargeAt,
          wageAt: widget.wageAt,
        );
        netSum += summary.net;
      } else {
        final allSchedules =
            widget.schedules.where((s) => s.albaId == aid).toList();
        final summary = const PayrollEngine().summaryForDate(
          policy: payroll,
          alba: alba,
          schedules: allSchedules,
          tax: tax,
          insurance: ins,
          surchargePolicy: polc,
          wageAt: widget.wageAt,
          surchargeAt: surchargeAt,
          taxAt: widget.getTaxAt?.call(aid),
          insuranceAt: widget.getInsuranceAt?.call(aid),
          anyDateInPeriod: _focusedDay,
        );
        netSum += summary.net;
      }
    }

    final theme = Theme.of(context);
    _buildPayMarksForMonth(_focusedDay.year, _focusedDay.month);
    _buildJuhuMarksForMonth(_focusedDay.year, _focusedDay.month);

    final weeks = _weeksInMonthGrid(_focusedDay);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: Color(0xFF111827),
                ),
                onPressed: widget.onBack!,
              )
            : null,
        title: const Text(
          AppWords.calendar,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _TossCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: AppWords.prevMonth,
                          onPressed: () => setState(() {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month - 1,
                              1,
                            );
                            _selectedDay = null;
                          }),
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
                          onPressed: () => setState(() {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month + 1,
                              1,
                            );
                            _selectedDay = null;
                          }),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          '예상 수령',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_comma(netSum)}원',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 28,
                      child: widget.albas.isNotEmpty
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Builder(
                                builder: (ctx) {
                                  final albasInMonth = widget.albas
                                      .where(
                                        (a) => widget.schedules.any(
                                          (s) =>
                                              s.albaId == a.id &&
                                              s.year == _focusedDay.year &&
                                              s.month == _focusedDay.month,
                                        ),
                                      )
                                      .toList();
                                  if (albasInMonth.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Row(
                                    children: albasInMonth.map((a) {
                                      final on = activeIds.contains(a.id);
                                      final c = cp.parseColor(a.colorHex);
                                      return GestureDetector(
                                        onTap: () => setState(() {
                                          if (on) {
                                            activeIds.remove(a.id);
                                          } else {
                                            activeIds.add(a.id);
                                          }
                                          _payYmKey = '';
                                          _juhuYmKey = '';
                                        }),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          margin:
                                              const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: on ? c : c.withOpacity(0.10),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            a.name,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: on ? Colors.white : c,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _TossCard(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -250) {
                        setState(() {
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month + 1,
                            1,
                          );
                          _selectedDay = null;
                        });
                      } else if (v > 250) {
                        setState(() {
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month - 1,
                            1,
                          );
                          _selectedDay = null;
                        });
                      }
                    },
                    child: Column(
                      children: [
                        const _CalDowHeader(),
                        Container(
                          height: 0.5,
                          color: const Color(0xFFE5E7EB),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              for (int w = 0; w < weeks; w++) ...[
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (int d = 0; d < 7; d++) ...[
                                        Expanded(
                                          child: Builder(
                                            builder: (ctx) {
                                              final day = _gridDayAt(w, d);
                                              final isOutside = day.month !=
                                                  _focusedDay.month;
                                              final isToday = _dateOnly(day) ==
                                                  _dateOnly(DateTime.now());
                                              final isSelected = _selectedDay !=
                                                      null &&
                                                  _dateOnly(day) ==
                                                      _dateOnly(_selectedDay!);

                                              return GestureDetector(
                                                onTap: () async {
                                                  final ev = _eventsOf(day);
                                                  setState(
                                                      () => _selectedDay = day);
                                                  await _onTapDay(day, ev);
                                                  if (!mounted) return;
                                                  setState(() =>
                                                      _selectedDay = null);
                                                },
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      right: d < 6
                                                          ? const BorderSide(
                                                              color: Color(
                                                                  0xFFE5E7EB),
                                                              width: 1.0,
                                                            )
                                                          : BorderSide.none,
                                                    ),
                                                  ),
                                                  child: _dayCell(
                                                    ctx,
                                                    day,
                                                    isToday: isToday,
                                                    isSelected: isSelected,
                                                    isOutside: isOutside,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (w < weeks - 1)
                                  Container(
                                    height: 1.0,
                                    color: const Color(0xFFE5E7EB),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
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

/* ───────────────────────── 아래 위젯들 ───────────────────────── */

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
        for (int i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: _GupBadge(color: shown[i].color),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 3),
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

  void _showPayDaySheet(BuildContext context, List<_PayMark> marks) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '급여일',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              for (final m in marks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: m.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.albaName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${m.periodStart.month}/${m.periodStart.day} ~ ${m.periodEnd.month}/${m.periodEnd.day}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_comma(m.net)}원',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: m.color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GupBadge extends StatelessWidget {
  const _GupBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        '급여',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

class _InlineJuhuBadges extends StatelessWidget {
  const _InlineJuhuBadges({required this.marks});
  final List<_JuhuMark> marks;

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) return const SizedBox.shrink();

    final shown = marks.take(2).toList();
    final more = marks.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: _JuhuPill(color: shown[i].color),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              '+$more',
              style:
                  Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
            ),
          ),
      ],
    );
  }

  void _showJuhuSheet(BuildContext context, List<_JuhuMark> marks) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '주휴수당',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              for (final m in marks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: m.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m.albaName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${_comma(m.juhuPay)}원',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: m.color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JuhuPill extends StatelessWidget {
  const _JuhuPill({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        '주휴',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.1,
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
      height: 16,
      margin: const EdgeInsets.only(top: 1, left: 1, right: 1),
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
      clipBehavior: Clip.hardEdge,
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
    this.wageAt,
  });

  final UICalendarAlba alba;
  final Color color;
  final _MergedBlock block;
  final DateTime localDate;

  final void Function(String scheduleId) onEdit;
  final void Function(String scheduleId) onDelete;

  final bool readOnly;
  final int Function(String albaId, DateTime dateLocal)? wageAt;

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
    final firstSchedule = b.children.isNotEmpty ? b.children.first : null;
    final effectiveWage = firstSchedule?.overrideHourlyWage ??
        widget.wageAt?.call(widget.alba.id, widget.localDate) ??
        widget.alba.hourlyWage;

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
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: widget.color.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${_commaInt(effectiveWage)}원/시',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: widget.color,
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
                  height: 1,
                  color: theme.dividerColor.withOpacity(0.35),
                ),
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
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFF43F5E)),
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
