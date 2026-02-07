// lib/common/common_pickers.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // PointerScrollEvent
import 'package:table_calendar/table_calendar.dart'; // ← TableCalendar

/* ---------------------------------------------------------------------------
 * 공통 유틸
 * -------------------------------------------------------------------------*/

/// HEX → Color
Color parseColor(String hex) {
  var s = hex.replaceAll('#', '').toUpperCase();
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join(); // #abc → #aabbcc
  }
  if (s.length == 6) s = 'FF$s'; // alpha 기본값
  final v = int.tryParse(s, radix: 16) ?? 0xFF3B82F6;
  return Color(v);
}

/// AM/PM 포맷
String fmtAmPm(int h24, int m) {
  final h = h24 % 24;
  final ap = h < 12 ? '오전' : '오후';
  final hh = (h % 12 == 0) ? 12 : (h % 12);
  final mm = m.toString().padLeft(2, '0');
  return '$ap $hh:$mm';
}

/// 내부: 24h → (am(0)/pm(1), 1~12, 0~59)
(int ap, int h12, int m) _to12(int h24, int m) {
  final ap = h24 < 12 ? 0 : 1;
  final h = h24 % 12;
  final h12 = h == 0 ? 12 : h;
  return (ap, h12, m.clamp(0, 59));
}

/// 내부: (am(0)/pm(1), 1~12, 0~59) → 24h
(int h24, int m) _to24(int ap, int h12, int m) {
  int h = h12 % 12; // 12 → 0
  if (ap == 1) h += 12;
  return (h, m.clamp(0, 59));
}

/* ---------------------------------------------------------------------------
 * 시간 설정 (갤럭시/아이폰 휠 느낌) - 다이얼로그
 * -------------------------------------------------------------------------*/
Future<void> showTimeSheet({
  required BuildContext context,
  required int startH,
  required int startM,
  required int endH,
  required int endM,
  required void Function(int startH, int startM, int endH, int endM) onDone,
}) async {
  var (sAp, sH12, sMin) = _to12(startH, startM);
  var (eAp, eH12, eMin) = _to12(endH, endM);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                void onStartChange(int ap, int h, int m) {
                  sAp = ap;
                  sH12 = h;
                  sMin = m;
                  setState(() {});
                }

                void onEndChange(int ap, int h, int m) {
                  eAp = ap;
                  eH12 = h;
                  eMin = m;
                  setState(() {});
                }

                final (sh, sm) = _to24(sAp, sH12, sMin);
                final (eh, em) = _to24(eAp, eH12, eMin);
                final nextDay = (eh * 60 + em) <= (sh * 60 + sm);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 헤더
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('취소'),
                        ),
                        const Spacer(),
                        Text('근무시간',
                            style: Theme.of(ctx).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            onDone(sh, sm, eh, em);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('완료'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // 본문: 시작/종료 휠
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text('시작',
                                  style: Theme.of(ctx).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              _TimeSection12h(
                                ap: sAp,
                                h12: sH12,
                                min: sMin,
                                onChange: onStartChange,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 180,
                          child: VerticalDivider(
                            width: 24,
                            thickness: 1,
                            color: Theme.of(ctx).dividerColor,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text('종료',
                                  style: Theme.of(ctx).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              _TimeSection12h(
                                ap: eAp,
                                h12: eH12,
                                min: eMin,
                                onChange: onEndChange,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    // 하단 프리뷰(실시간)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${fmtAmPm(sh, sm)} ~ ${fmtAmPm(eh, em)}',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (nextDay) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(다음날)',
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

class _TimeSection12h extends StatefulWidget {
  const _TimeSection12h({
    required this.ap,
    required this.h12,
    required this.min,
    required this.onChange,
  });

  final int ap; // 0=오전, 1=오후
  final int h12; // 1..12
  final int min; // 0..59
  final void Function(int ap, int h12, int m) onChange;

  @override
  State<_TimeSection12h> createState() => _TimeSection12hState();
}

class _TimeSection12hState extends State<_TimeSection12h> {
  static const double _itemExtent = 40;

  late FixedExtentScrollController _apCtrl;
  late FixedExtentScrollController _hCtrl;
  late FixedExtentScrollController _mCtrl;

  late int _ap;
  late int _h12;
  late int _m;

  @override
  void initState() {
    super.initState();
    _ap = widget.ap.clamp(0, 1);
    _h12 = widget.h12.clamp(1, 12);
    _m = widget.min.clamp(0, 59);
    _apCtrl = FixedExtentScrollController(initialItem: _ap);
    _hCtrl = FixedExtentScrollController(initialItem: _h12 - 1);
    _mCtrl = FixedExtentScrollController(initialItem: _m);
  }

  @override
  void dispose() {
    _apCtrl.dispose();
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Wheel(
          width: 70,
          itemExtent: _itemExtent,
          controller: _apCtrl,
          count: 2,
          initialIndex: _ap,
          display: (i) => i == 0 ? '오전' : '오후',
          onChanged: (i) {
            setState(() => _ap = i);
            widget.onChange(_ap, _h12, _m);
          },
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _Wheel(
            itemExtent: _itemExtent,
            controller: _hCtrl,
            count: 12,
            initialIndex: _h12 - 1,
            display: (i) => (i + 1).toString().padLeft(2, '0'),
            onChanged: (i) {
              setState(() => _h12 = i + 1);
              widget.onChange(_ap, _h12, _m);
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _Wheel(
            itemExtent: _itemExtent,
            controller: _mCtrl,
            count: 60,
            initialIndex: _m,
            display: (i) => i.toString().padLeft(2, '0'),
            onChanged: (i) {
              setState(() => _m = i);
              widget.onChange(_ap, _h12, _m);
            },
          ),
        ),
      ],
    );
  }
}

/// 드래그/마우스휠 강화 휠
class _Wheel extends StatefulWidget {
  const _Wheel({
    this.width,
    required this.itemExtent,
    required this.controller,
    required this.count,
    required this.initialIndex,
    required this.display,
    required this.onChanged,
  });

  final double? width;
  final double itemExtent;
  final FixedExtentScrollController controller;
  final int count;
  final int initialIndex;
  final String Function(int index) display;
  final ValueChanged<int> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late int _current;
  double _dragAccum = 0.0;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.count - 1);
  }

  void _jumpBy(int delta) {
    if (delta == 0) return;
    final next = (_current + delta).clamp(0, widget.count - 1);
    if (next == _current) return;
    _current = next;
    _animating = true;
    widget.controller
        .animateToItem(
      _current,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
    )
        .whenComplete(() {
      _animating = false;
      widget.onChanged(_current);
    });
  }

  void _onDragUpdate(double dy) {
    _dragAccum += dy;
    final step = (_dragAccum / widget.itemExtent).truncate();
    if (step.abs() >= 1 && !_animating) {
      _dragAccum -= step * widget.itemExtent;
      _jumpBy(step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wheel = SizedBox(
      height: 170,
      child: ListWheelScrollView.useDelegate(
        controller: widget.controller,
        itemExtent: widget.itemExtent,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          _current = i;
          widget.onChanged(_current);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.count,
          builder: (_, i) => Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.display(i),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );

    final interactive = Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          if (signal.scrollDelta.dy > 0) {
            _jumpBy(1);
          } else if (signal.scrollDelta.dy < 0) {
            _jumpBy(-1);
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _dragAccum = 0.0,
        onVerticalDragUpdate: (d) => _onDragUpdate(d.delta.dy),
        onVerticalDragEnd: (_) => _dragAccum = 0.0,
        child: wheel,
      ),
    );

    if (widget.width != null)
      return SizedBox(width: widget.width, child: interactive);
    return interactive;
  }
}

/* ---------------------------------------------------------------------------
 * 휴게시간(0/30/60/직접입력) - 팝업 다이얼로그
 * -------------------------------------------------------------------------*/
Future<void> showBreakSheet({
  required BuildContext context,
  required int initialMinutes,
  required ValueChanged<int> onDone,
}) async {
  int cur = initialMinutes.clamp(0, 600);
  String mode = (cur == 0 || cur == 30 || cur == 60) ? '$cur' : 'custom';
  String customText = mode == 'custom' ? cur.toString() : '';

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                void select(String m) {
                  setState(() {
                    mode = m;
                    if (m != 'custom') {
                      cur = int.parse(m);
                      customText = '';
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('취소'),
                        ),
                        const Spacer(),
                        Text('휴게 시간',
                            style: Theme.of(ctx).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            onDone(cur);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('완료'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _seg('0분', mode == '0', () => select('0')),
                        _seg('30분', mode == '30', () => select('30')),
                        _seg('60분', mode == '60', () => select('60')),
                        _seg('직접입력', mode == 'custom', () => select('custom')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (mode == 'custom')
                      TextField(
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '분(숫자)',
                          hintText: '예: 45',
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(text: customText)
                          ..selection = TextSelection.collapsed(
                              offset: customText.length),
                        onChanged: (s) {
                          final v = int.tryParse(
                                  s.replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0;
                          cur = v.clamp(0, 600);
                          customText = cur == 0 ? '' : cur.toString();
                        },
                      ),
                    const SizedBox(height: 12),
                    Text('선택: ${cur}분',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

Widget _seg(String text, bool on, VoidCallback tap) {
  return ChoiceChip(
    label: Text(text),
    selected: on,
    onSelected: (_) => tap(),
  );
}

/* ---------------------------------------------------------------------------
 * 급여일 시트
 * -------------------------------------------------------------------------*/
Future<void> showPaydaySheet({
  required BuildContext context,
  required int initialDay,
  required ValueChanged<int> onDone,
}) async {
  int cur = initialDay.clamp(1, 31);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final ctrl = FixedExtentScrollController(initialItem: cur - 1);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('취소'),
                        ),
                        const Spacer(),
                        Text('급여일', style: Theme.of(ctx).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            onDone(cur);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('완료'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 40,
                        physics: const FixedExtentScrollPhysics(),
                        controller: ctrl,
                        onSelectedItemChanged: (i) =>
                            setState(() => cur = i + 1),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 31,
                          builder: (_, i) => Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .surfaceVariant
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${i + 1}',
                                  style: Theme.of(ctx).textTheme.titleMedium),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '매월 $cur일',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

/* ─────────────────────────────────────────────────────────────────
 * TableCalendar 기반 멀티 날짜 선택 다이얼로그
 *  - 포맷 전환 버튼(2 weeks/Week) 제거, YYYY년 M월만 노출
 *  - 요일 라벨 절대 안 잘리도록 높이/라인 높이 조정
 *  - 오늘: 초록색 숫자 / 오늘이 비활성일 경우 연한 초록색
 * ────────────────────────────────────────────────────────────────*/
Future<Set<DateTime>?> showAlbaDatePickerDialog(
  BuildContext context, {
  Set<DateTime>? initialUtc,
  DateTime? initialFocusedDay,
  DateTime? firstDay,
  DateTime? lastDay,
  bool Function(DateTime utc)? checkConflict, // true면 비활성화
}) {
  return showDialog<Set<DateTime>>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AlbaMultiDateDialog(
      initialUtc: initialUtc ?? <DateTime>{},
      focused: initialFocusedDay ?? DateTime.now(),
      firstDay: firstDay ?? DateTime.utc(2010, 1, 1),
      lastDay: lastDay ?? DateTime.utc(2035, 12, 31),
      checkConflict: checkConflict,
    ),
  );
}

class _AlbaMultiDateDialog extends StatefulWidget {
  const _AlbaMultiDateDialog({
    required this.initialUtc,
    required this.focused,
    required this.firstDay,
    required this.lastDay,
    this.checkConflict,
  });

  final Set<DateTime> initialUtc;
  final DateTime focused;
  final DateTime firstDay;
  final DateTime lastDay;
  final bool Function(DateTime utc)? checkConflict;

  @override
  State<_AlbaMultiDateDialog> createState() => _AlbaMultiDateDialogState();
}

class _AlbaMultiDateDialogState extends State<_AlbaMultiDateDialog> {
  late DateTime _focusedDay;
  late Set<DateTime> _selectedUtc; // UTC 00:00 집합

  @override
  void initState() {
    super.initState();
    _focusedDay = _dateOnly(widget.focused);
    _selectedUtc = widget.initialUtc.map(_dateOnlyUtc).toSet();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dateOnlyUtc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  bool _isSelectedLocal(DateTime localDay) {
    return _selectedUtc.any((u) =>
        u.year == localDay.year &&
        u.month == localDay.month &&
        u.day == localDay.day);
  }

  bool _isDisabledLocal(DateTime localDay) {
    if (widget.checkConflict == null) return false;
    final utc = _dateOnlyUtc(localDay);
    return widget.checkConflict!(utc);
  }

  bool _isToday(DateTime localDay) {
    final now = DateTime.now();
    return now.year == localDay.year &&
        now.month == localDay.month &&
        now.day == localDay.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TableCalendar(
                locale: 'ko_KR',
                firstDay: widget.firstDay,
                lastDay: widget.lastDay,
                focusedDay: _focusedDay,

                headerVisible: true,
                calendarFormat: CalendarFormat.month,
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  leftChevronVisible: true,
                  rightChevronVisible: true,
                  headerPadding: const EdgeInsets.symmetric(vertical: 8),
                  titleTextFormatter: (date, locale) =>
                      '${date.year}년 ${date.month}월',
                  titleTextStyle: theme.textTheme.titleMedium!,
                ),
                startingDayOfWeek: StartingDayOfWeek.sunday,

                // ✅ 요일 라벨 안 잘림: 높이+라인높이+overflow 조정
                daysOfWeekHeight: 28,
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekendStyle: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                  weekdayStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),

                // 멀티선택: predicate로 표시, onDaySelected에서 토글
                selectedDayPredicate: (day) => _isSelectedLocal(day),
                onDaySelected: (selectedDay, focusedDay) {
                  final dLocal = _dateOnly(selectedDay);
                  if (_isDisabledLocal(dLocal)) return;

                  final u = _dateOnlyUtc(dLocal);
                  setState(() {
                    if (_selectedUtc.contains(u)) {
                      _selectedUtc.remove(u);
                    } else {
                      _selectedUtc.add(u);
                    }
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (fd) => _focusedDay = fd,

                enabledDayPredicate: (day) => !_isDisabledLocal(day),

                // 셀 렌더링 커스텀(오늘/비활성/기본)
                calendarBuilders: CalendarBuilders(
                  // 요일 헤더(일=빨강, 토=파랑) - overflow 방지
                  dowBuilder: (ctx, day) {
                    const labels = ['일', '월', '화', '수', '목', '금', '토'];
                    final idx = day.weekday % 7;
                    final isSun = idx == 0;
                    final isSat = idx == 6;
                    final color = isSun
                        ? Colors.redAccent
                        : isSat
                            ? Colors.blueAccent
                            : theme.colorScheme.onSurface.withOpacity(0.75);
                    return Center(
                      child: Text(
                        labels[idx],
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    );
                  },

                  // 오늘: 초록색 텍스트, 도형 데코 없음
                  todayBuilder: (ctx, day, _) {
                    final disabled = _isDisabledLocal(day);
                    final color = disabled
                        ? Colors.green.withOpacity(0.45)
                        : Colors.green;
                    return Center(
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },

                  // 비활성 셀: 회색(오늘은 위 todayBuilder에서 처리해 연한 초록)
                  disabledBuilder: (ctx, day, _) {
                    final isToday = _isToday(day);
                    if (isToday) {
                      // 오늘+비활성 → 연한 초록색
                      return Center(
                        child: Text(
                          '${day.day}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green.withOpacity(0.45),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.30),
                        ),
                      ),
                    );
                  },

                  // 일반 셀(일/토 색상)
                  defaultBuilder: (ctx, day, _) {
                    final isSun = day.weekday == DateTime.sunday;
                    final isSat = day.weekday == DateTime.saturday;
                    final color = isSun
                        ? Colors.redAccent
                        : isSat
                            ? Colors.blueAccent
                            : theme.colorScheme.onSurface;
                    return Center(
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),

                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  isTodayHighlighted: true, // todayBuilder로 렌더링
                  // todayDecoration은 todayBuilder를 쓰므로 의미 없음(투명)
                  todayDecoration: const BoxDecoration(),
                  selectedDecoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // 하단 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('취소'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final out = _selectedUtc.toList()
                          ..sort((a, b) => a.compareTo(b));
                        Navigator.of(context).pop(out.toSet());
                      },
                      child: const Text('적용'),
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
