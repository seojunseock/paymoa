// lib/screens/alba_start_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/ui_calendar_models.dart';
import '../common/common_pickers.dart' as cp;
import '../policies/policies.dart' as pol; // 정책 타입
import 'work_editor_args.dart' as wargs;

/* ───────────────── 날짜 아래 “매장색 점” ───────────────── */
class _DotEvent {
  final Color color;
  final String albaName;
  const _DotEvent(this.color, this.albaName);
}

/* ───────────────── 공용 포맷터 ───────────────── */
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

String _workTypeLabel(WorkType t) {
  switch (t) {
    case WorkType.basic:
      return '기본근무';
    case WorkType.substitute:
      return '대타근무';
    case WorkType.overtime:
      return '연장근무';
    case WorkType.holiday:
      return '휴일근무';
    case WorkType.night:
      return '야간근무';
    case WorkType.weekly:
      return '주휴수당';
  }
}

/* ───────────────── 날짜 상세 병합 블록 ───────────────── */
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
    if (s.albaId != albaId || s.year != year || s.month != month || s.day != day) {
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

/* ───────────────── 바텀시트 카드(달력 화면 스타일 복제) ───────────────── */
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

    final rangeText =
        _timeRangeText(b.startHour, b.startMinute, b.endHour, b.endMinute);
    final minutes = b.totalWorkedMinutes;
    final infoText = '${_hoursText(minutes)} · ${_comma(widget.basePay)}원';

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
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              icon:
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
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
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      dense: true,
                      title: Text(
                          '${_workTypeLabel(s.workType)}  $st~$et  ($wt)'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                              onPressed: () => widget.onEdit(s.id),
                              child: const Text('편집')),
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

  int _workedMinutes(UICalendarSchedule s) {
    final start = Duration(hours: s.startHour, minutes: s.startMinute);
    var end = Duration(hours: s.endHour, minutes: s.endMinute);
    var diff = end - start;
    if (diff.isNegative) diff += const Duration(days: 1);
    final worked = diff.inMinutes - (s.breakMinutes).clamp(0, diff.inMinutes);
    return worked.clamp(0, 24 * 60);
  }
}

/* ───────────────── 화면 ───────────────── */
class AlbaStartScreen extends StatefulWidget {
  const AlbaStartScreen({
    super.key,
    required this.albas,
    required this.schedules,
    required this.onBack, // 현재는 미사용
    required this.onGoToAlbaForm,
    required this.onEditAlba,
    required this.onOpenWorkEditor,
    required this.onDeleteSchedule, // 바텀시트 내 스케줄 삭제
    required this.onDeleteAlba, // ⬅️ 신규: 알바 전체 삭제
    this.getTaxPolicy,
    this.getInsurancePolicy,
    this.getSurchargePolicy,
  });

  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final VoidCallback onBack;
  final VoidCallback onGoToAlbaForm;
  final void Function(String albaId) onEditAlba;
  final void Function(wargs.WorkEditorArgs) onOpenWorkEditor;
  final void Function(String scheduleId) onDeleteSchedule;
  final void Function(String albaId) onDeleteAlba;

  // 선택: 정책 표시에 사용 (AppShell에서 실제 타입을 전달)
  final Object? Function(String albaId)? getTaxPolicy;
  final Object? Function(String albaId)? getInsurancePolicy;
  final Object? Function(String albaId)? getSurchargePolicy;

  @override
  State<AlbaStartScreen> createState() => _AlbaStartScreenState();
}

class _AlbaStartScreenState extends State<AlbaStartScreen> {
  // ── 주간 달력 상태 ──
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = null;
  }

  /* ── 달력 점 이벤트 ── */
  List<_DotEvent> _getDotsForDay(DateTime day) {
    final y = day.year, m = day.month, d = day.day;
    final byAlba = <String, _DotEvent>{};
    for (final s in widget.schedules) {
      if (s.year == y && s.month == m && s.day == d) {
        final alba = widget.albas.firstWhere(
          (a) => a.id == s.albaId,
          orElse: () => UICalendarAlba(
              id: s.albaId,
              name: '',
              colorHex: '#3B82F6',
              hourlyWage: 0),
        );
        byAlba.putIfAbsent(
          alba.id,
          () => _DotEvent(cp.parseColor(alba.colorHex), alba.name),
        );
      }
    }
    return byAlba.values.take(4).toList();
  }

  /* ── 날짜 탭 → “달력 화면과 동일한 바텀시트” ── */
  void _onTapDay(DateTime selectedDay, DateTime focusedDay) {
    _selectedDay = null;
    setState(() {});
    final y = selectedDay.year, m = selectedDay.month, d = selectedDay.day;
    final localDate = DateTime(y, m, d);

    // 알바별 그룹 & 연속 병합
    final groupedByAlba = <String, List<UICalendarSchedule>>{};
    for (final s in widget.schedules.where(
        (s) => s.year == y && s.month == m && s.day == d)) {
      groupedByAlba.putIfAbsent(s.albaId, () => []).add(s);
    }

    showModalBottomSheet<void>(
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
                name: '',
                colorHex: '#3B82F6',
                hourlyWage: 0),
          );
          final color = cp.parseColor(alba.colorHex);
          final list = [...entry.value]
            ..sort((a, b) => (a.startHour * 60 + a.startMinute)
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
            final minutes = block.totalWorkedMinutes;
            final wagePerHour = alba.hourlyWage; // 날짜별 스냅샷이 있으면 교체
            final basePay = (wagePerHour * minutes) ~/ 60;

            cards.add(
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border(left: BorderSide(color: color, width: 3)),
                ),
                child: _ExpandableMergedCard(
                  alba: alba,
                  color: color,
                  block: block,
                  localDate: localDate,
                  basePay: basePay,
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
                  onDelete: (scheduleId) {
                    widget.onDeleteSchedule(scheduleId);
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
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('선택한 날짜에 근무가 없습니다.'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onOpenWorkEditor(
                        wargs.WorkEditorArgs(
                          mode: wargs.WorkEditorArgsMode.add,
                          presetDate: localDate,
                        ),
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
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${localDate.year}.${localDate.month.toString().padLeft(2, '0')}.${localDate.day.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '근무 추가',
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onOpenWorkEditor(
                            wargs.WorkEditorArgs(
                                mode: wargs.WorkEditorArgsMode.add,
                                presetDate: localDate),
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ...cards,
              ],
            ),
          ),
        );
      },
    );
  }

  /* ── 정책/요약 도우미 ── */
  pol.TaxConfig _taxOf(String id) =>
      (widget.getTaxPolicy?.call(id) as pol.TaxConfig?) ??
      pol.TaxConfig.none;
  pol.InsuranceConfig _insOf(String id) =>
      (widget.getInsurancePolicy?.call(id) as pol.InsuranceConfig?) ??
      const pol.InsuranceNone();
  pol.SurchargePolicy? _surOf(String id) =>
      (widget.getSurchargePolicy?.call(id) as pol.SurchargePolicy?);

  bool _anySurchargeEnabled(pol.SurchargePolicy? s) {
    if (s == null) return false;
    return s.weeklyHolidayEnabled ||
        s.overtimeEnabled ||
        s.holidayEnabled ||
        s.nightEnabled;
  }

  bool _hasAnyPolicy(
      pol.TaxConfig t, pol.InsuranceConfig i, pol.SurchargePolicy? s) {
    final hasTax = t != pol.TaxConfig.none;
    final hasIns = i is! pol.InsuranceNone;
    final hasSur = _anySurchargeEnabled(s);
    return hasTax || hasIns || hasSur;
  }

  String _labelTax(pol.TaxConfig t) {
    if (t == pol.TaxConfig.none) return '없음';
    if (t == pol.TaxConfig.biz33) return '사업소득 3.3%';
    if (t == pol.TaxConfig.day66) return '일용직 6.6%';
    if (t is pol.TaxConfigCustomPercent) {
      return '직접입력 ${_trimPct(t.percent)}%';
    }
    return '세금 설정';
  }

  String _labelIns(pol.InsuranceConfig i) {
    if (i is pol.InsuranceNone) return '없음';
    if (i is pol.InsuranceEmploymentOnly) return '고용보험만';
    if (i is pol.InsuranceFour) return '4대보험';
    return '보험 설정';
  }

  String _labelSurcharge(pol.SurchargePolicy? s) {
    if (!_anySurchargeEnabled(s)) return '없음';
    final list = <String>[];
    if (s!.weeklyHolidayEnabled) list.add('주휴');
    if (s.overtimeEnabled) {
      list.add('연장 +${_trimPct(s.overtimePercent)}%');
    }
    if (s.holidayEnabled) {
      list.add('휴일 +${_trimPct(s.holidayPercent)}%');
    }
    if (s.nightEnabled) {
      list.add('야간 +${_trimPct(s.nightPercent)}%');
    }
    return list.join(', ');
  }

  /* ── 합계/작업시간/통화 ── */
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

  /* ── UI ── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: null,
        actions: [
          TextButton(
              onPressed: widget.onGoToAlbaForm, child: const Text('알바 등록'))
        ],
      ),
      body: Column(
        children: [
          // ── 주간 달력 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: _WeeklyCalendarBox(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              onDaySelected: _onTapDay, // 날짜 탭 시 바텀시트
              onPageChanged: (fd) => setState(() => _focusedDay = fd),
              eventLoader: (day) => _getDotsForDay(day),
            ),
          ),

          // ── 알바 카드 목록 ──
          Expanded(
            child: widget.albas.isEmpty
                ? const _EmptyView()
                : ListView.builder(
                    itemCount: widget.albas.length,
                    itemBuilder: (context, index) {
                      final alba = widget.albas[index];
                      final color = cp.parseColor(alba.colorHex);
                      final todayGross =
                          _calcGrossUntilToday(alba, widget.schedules);

                      final tax = _taxOf(alba.id);
                      final ins = _insOf(alba.id);
                      final sur = _surOf(alba.id);
                      final hasPolicy = _hasAnyPolicy(tax, ins, sur);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color, width: 1.5), // 테두리만 색상
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey(alba.id),
                            tilePadding:
                                const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 14),

                            // trailing 미지정 → 기본 화살표(펼침/접힘 전환)
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${alba.name} (${alba.payDay}일)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('시급  ${_won(alba.hourlyWage)}',
                                    style: TextStyle(
                                        color: Colors.grey.shade700)),
                                const SizedBox(height: 2),
                                Text('오늘까지 급여  ${_won(todayGross)}',
                                    style: TextStyle(
                                        color: Colors.grey.shade700)),
                              ],
                            ),

                            // 펼침
                            children: [
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        widget.onEditAlba(alba.id),
                                    child: const Text('수정'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => widget.onOpenWorkEditor(
                                      wargs.WorkEditorArgs(
                                        mode:
                                            wargs.WorkEditorArgsMode.add,
                                        preselectedAlbaId: alba.id,
                                      ),
                                    ),
                                    child: const Text('근무 추가'),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: '알바 삭제',
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('알바를 삭제할까요?'),
                                          content: const Text(
                                              '해당 알바와 모든 근무기록이 삭제됩니다. 되돌릴 수 없습니다.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      ctx, false),
                                              child: const Text('취소'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      ctx, true),
                                              child: const Text('삭제'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        widget.onDeleteAlba(alba.id);
                                      }
                                    },
                                    icon: const Icon(
                                        Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (!hasPolicy)
                                _kv('${_focusedDay.month}월 총 근무일수',
                                    '${_totalWorkDaysOfMonth(alba.id)}회')
                              else ...[
                                _kv('세금', _labelTax(tax)),
                                _kv('보험', _labelIns(ins)),
                                _kv('가산정책', _labelSurcharge(sur)),
                                _kv('${_focusedDay.month}월 총 근무일수',
                                    '${_totalWorkDaysOfMonth(alba.id)}회'),
                              ],
                            ],
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

/* ───────────────── 주간 캘린더 위젯 ───────────────── */
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
  final void Function(DateTime selectedDay, DateTime focusedDay)
      onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final List<dynamic> Function(DateTime day) eventLoader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color _weekdayColor(DateTime day) {
      if (day.weekday == DateTime.sunday) return Colors.redAccent;
      if (day.weekday == DateTime.saturday) return Colors.blueAccent;
      return theme.colorScheme.onSurface;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
        daysOfWeekHeight: 28,
        selectedDayPredicate: (_) => false,
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        eventLoader: eventLoader,
        calendarBuilders: CalendarBuilders(
          dowBuilder: (ctx, day) {
            const labels = ['일', '월', '화', '수', '목', '금', '토'];
            final label = labels[day.weekday % 7];
            final isSun = day.weekday == DateTime.sunday;
            final isSat = day.weekday == DateTime.saturday;
            final color = isSun
                ? Colors.redAccent
                : isSat
                    ? Colors.blueAccent
                    : theme.colorScheme.onSurface.withOpacity(0.75);
            return Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.visible,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            );
          },
          defaultBuilder: (ctx, day, _) => Center(
            child: Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _weekdayColor(day),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          todayBuilder: (ctx, day, _) => Center(
            child: Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            final dots = events.whereType<_DotEvent>().toList();
            if (dots.isEmpty) return const SizedBox.shrink();
            const double size = 6;
            const double gap = 4;
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(dots.length, (i) {
                  return Container(
                    width: size,
                    height: size,
                    margin: EdgeInsets.only(
                        right: i == dots.length - 1 ? 0 : gap),
                    decoration: BoxDecoration(
                        color: dots[i].color, shape: BoxShape.circle),
                  );
                }),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          isTodayHighlighted: true,
          markersMaxCount: 4,
          markersAlignment: Alignment.bottomCenter,
          markersOffset: PositionedOffset(bottom: 6),
        ),
      ),
    );
  }
}

/* ───────────────── 공용 작은 위젯/유틸 ───────────────── */
Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
            child: Text(k, style: const TextStyle(color: Colors.grey))),
        Text(v, textAlign: TextAlign.right),
      ],
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.work_outline, size: 64),
            const SizedBox(height: 12),
            const Text('등록된 알바가 없습니다.'),
            const SizedBox(height: 8),
            Text(
              '오른쪽 상단의 “알바 등록” 버튼을 눌러 시작해 보세요.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
