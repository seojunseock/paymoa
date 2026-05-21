// lib/common/common_pickers.dart
import 'package:flutter/cupertino.dart';
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
   휴게시간 피커 — iOS Cupertino 롤 방식 (5분 단위, 0~120분)
--------------------------------------------------------------------------- */

Future<void> showBreakSheet({
  required BuildContext context,
  required int initialMinutes,
  required ValueChanged<int> onDone,
}) async {
  // 5분 단위로 정규화 (0, 5, 10, …, 120 → 총 25개)
  final initItem = ((initialMinutes.clamp(0, 120) / 5).round()).clamp(0, 24);
  final controller = FixedExtentScrollController(initialItem: initItem);
  int selected = initItem * 5;

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Row(
                children: [
                  const Text(
                    '휴게시간',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    selected == 0 ? '없음' : '$selected분',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // iOS 롤러
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 52,
                    looping: false,
                    selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                      background: const Color(0xFF7C3AED).withOpacity(0.09),
                    ),
                    onSelectedItemChanged: (i) {
                      setS(() => selected = i * 5);
                    },
                    children: List.generate(25, (i) {
                      final m = i * 5;
                      return Center(
                        child: Text(m == 0 ? '없음  (0분)' : '$m분'),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 확인 버튼
              SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      onDone(selected);
                      Navigator.of(ctx).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      });
    },
  );

  controller.dispose();
}

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
    barrierDismissible: false,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      child: const Text('취소',
                          style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        final out = _selectedUtc.toList()
                          ..sort((a, b) => a.compareTo(b));
                        Navigator.of(context).pop(out.toSet());
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFEDE9FE),
                        foregroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('적용',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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

/* ═══════════════════════════════════════════════
   단일 날짜 선택 다이얼로그 (시급 적용일 선택용)
   ═══════════════════════════════════════════════ */

Future<DateTime?> showSingleDatePickerDialog(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDay,
  DateTime? lastDay,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _SingleDateDialog(
      initial: initialDate ?? DateTime.now(),
      firstDay: firstDay ?? DateTime.utc(2010, 1, 1),
      lastDay: lastDay ?? DateTime.utc(2035, 12, 31),
    ),
  );
}

class _SingleDateDialog extends StatefulWidget {
  const _SingleDateDialog({
    required this.initial,
    required this.firstDay,
    required this.lastDay,
  });
  final DateTime initial;
  final DateTime firstDay;
  final DateTime lastDay;

  @override
  State<_SingleDateDialog> createState() => _SingleDateDialogState();
}

class _SingleDateDialogState extends State<_SingleDateDialog> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay =
        DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay2(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                selectedDayPredicate: (day) => _isSameDay2(_selectedDay, day),
                onDaySelected: (sel, foc) {
                  setState(() {
                    _selectedDay = _dateOnly(sel);
                    _focusedDay = foc;
                  });
                },
                onPageChanged: (fd) => setState(() => _focusedDay = fd),
                calendarBuilders: CalendarBuilders(
                  dowBuilder: (ctx, day) {
                    const labels = ['일', '월', '화', '수', '목', '금', '토'];
                    final idx = day.weekday % 7;
                    final color = idx == 0
                        ? Colors.redAccent
                        : idx == 6
                            ? Colors.blueAccent
                            : theme.colorScheme.onSurface.withOpacity(0.75);
                    return Center(
                      child: Text(labels[idx],
                          overflow: TextOverflow.visible,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                              height: 1.15)),
                    );
                  },
                  todayBuilder: (ctx, day, _) => Center(
                    child: Text('${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green, fontWeight: FontWeight.w800)),
                  ),
                  defaultBuilder: (ctx, day, _) {
                    final isSun = day.weekday == DateTime.sunday;
                    final isSat = day.weekday == DateTime.saturday;
                    final color = isSun
                        ? Colors.redAccent
                        : isSat
                            ? Colors.blueAccent
                            : theme.colorScheme.onSurface;
                    return Center(
                      child: Text('${day.day}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: color, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  isTodayHighlighted: true,
                  todayDecoration: const BoxDecoration(),
                  selectedDecoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('취소',
                          style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _selectedDay == null
                          ? null
                          : () => Navigator.of(context).pop(_selectedDay),
                      child: const Text('선택'),
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

/* ═══════════════════════════════════════════════════════
   아이폰 스타일 근무 시간 피커
   - 시작 / 종료 탭 전환
   - 큰 미리보기 숫자
   - 오전/오후 | 시 | 분(5분 단위) 3열 피커
   ═══════════════════════════════════════════════════════ */

class WorkTimeResult {
  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  const WorkTimeResult({
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
  });
}

Future<WorkTimeResult?> showWorkTimePicker(
  BuildContext context, {
  required int startHour24,
  required int startMinute,
  required int endHour24,
  required int endMinute,
}) {
  return showModalBottomSheet<WorkTimeResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _WorkTimePicker(
      startHour24: startHour24,
      startMinute: startMinute,
      endHour24: endHour24,
      endMinute: endMinute,
    ),
  );
}

/* ---------------------------------------------------------------------------
 * 색상 팔레트 Dialog
 * -------------------------------------------------------------------------*/

/// 색상 팔레트 Dialog 표시.
/// 선택된 hex('#XXXXXX' 대문자) 반환, 취소·바깥탭 시 null 반환.
Future<String?> showColorPaletteDialog({
  required BuildContext context,
  String initialHex = '#3B82F6',
}) {
  const colors = <String>[
    '#EF4444',
    '#F97316',
    '#F59E0B',
    '#EAB308',
    '#84CC16',
    '#22C55E',
    '#10B981',
    '#06B6D4',
    '#3B82F6',
    '#8B5CF6',
    '#EC4899',
    '#7C3AED',
  ];

  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('색상 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: colors.map((hex) {
                final selected =
                    hex.toUpperCase() == initialHex.toUpperCase();
                final c = parseColor(hex);
                return GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(hex.toUpperCase()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: c.withOpacity(selected ? 0.6 : 0.25),
                          blurRadius: selected ? 10 : 4,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                ),
                child: const Text('닫기',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkTimePicker extends StatefulWidget {
  const _WorkTimePicker({
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
  });
  final int startHour24, startMinute, endHour24, endMinute;

  @override
  State<_WorkTimePicker> createState() => _WorkTimePickerState();
}

class _WorkTimePickerState extends State<_WorkTimePicker> {
  // 0 = 시작, 1 = 종료
  int _tab = 0;

  // 시작
  late int _sAmpm; // 0=오전, 1=오후
  late int _sHour; // 1~12
  late int _sMinIdx; // 0~11 (5분 단위)

  // 종료
  late int _eAmpm;
  late int _eHour;
  late int _eMinIdx;

  // 피커 컨트롤러 (탭 전환 시 재생성 위해 key 사용)
  late FixedExtentScrollController _ampmCtrl;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;

  static const _minStep = 5; // 5분 단위
  static const _minCount = 60 ~/ _minStep; // 12개

  @override
  void initState() {
    super.initState();
    _sAmpm = widget.startHour24 < 12 ? 0 : 1;
    _sHour = _to12(widget.startHour24);
    _sMinIdx = (widget.startMinute ~/ _minStep).clamp(0, _minCount - 1);

    _eAmpm = widget.endHour24 < 12 ? 0 : 1;
    _eHour = _to12(widget.endHour24);
    _eMinIdx = (widget.endMinute ~/ _minStep).clamp(0, _minCount - 1);

    _buildControllers();
  }

  int _to12(int h24) {
    final h = h24 % 12;
    return h == 0 ? 12 : h;
  }

  int _to24(int ampm, int h12) {
    final h = h12 == 12 ? 0 : h12;
    return ampm == 0 ? h : h + 12;
  }

  void _buildControllers() {
    final ampm = _tab == 0 ? _sAmpm : _eAmpm;
    final hour = _tab == 0 ? _sHour : _eHour;
    final minIdx = _tab == 0 ? _sMinIdx : _eMinIdx;

    _ampmCtrl = FixedExtentScrollController(initialItem: ampm);
    _hourCtrl =
        FixedExtentScrollController(initialItem: hour - 1); // 1~12 → 0~11
    _minCtrl = FixedExtentScrollController(initialItem: minIdx);
  }

  void _disposeControllers() {
    _ampmCtrl.dispose();
    _hourCtrl.dispose();
    _minCtrl.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _switchTab(int tab) {
    if (_tab == tab) return;
    _disposeControllers();
    setState(() {
      _tab = tab;
      _buildControllers();
    });
  }

  String _fmt(int ampm, int h12, int minIdx) {
    final h24 = _to24(ampm, h12);
    final m = minIdx * _minStep;
    final ap = ampm == 0 ? '오전' : '오후';
    final hStr = h12.toString().padLeft(2, '0');
    final mStr = m.toString().padLeft(2, '0');
    return '$ap $hStr:$mStr';
  }

  // 총 근무 시간(분)
  int _totalMin() {
    final s = _to24(_sAmpm, _sHour) * 60 + _sMinIdx * _minStep;
    var e = _to24(_eAmpm, _eHour) * 60 + _eMinIdx * _minStep;
    if (e <= s) e += 24 * 60;
    return e - s;
  }

  @override
  Widget build(BuildContext context) {
    final isStart = _tab == 0;
    final dispAmpm = isStart ? _sAmpm : _eAmpm;
    final dispHour = isStart ? _sHour : _eHour;
    final dispMinIdx = isStart ? _sMinIdx : _eMinIdx;

    final totalMin = _totalMin();
    final totalH = totalMin ~/ 60;
    final totalM = totalMin % 60;
    final totalStr = totalM == 0 ? '$totalH시간' : '$totalH시간 $totalM분';

    return SafeArea(
      child: SizedBox(
        height: 430,
        child: Column(
          children: [
            // ── 헤더 ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소',
                        style: TextStyle(color: Color(0xFF6B7280))),
                  ),
                  const Spacer(),
                  const Text('근무 시간',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        WorkTimeResult(
                          startHour24: _to24(_sAmpm, _sHour),
                          startMinute: _sMinIdx * _minStep,
                          endHour24: _to24(_eAmpm, _eHour),
                          endMinute: _eMinIdx * _minStep,
                        ),
                      );
                    },
                    child: const Text('완료',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C3AED))),
                  ),
                ],
              ),
            ),

            // ── 시작/종료 탭 ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                      child: _TabBtn(
                    label: '시작',
                    time: _fmt(_sAmpm, _sHour, _sMinIdx),
                    active: isStart,
                    onTap: () => _switchTab(0),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _TabBtn(
                    label: '종료',
                    time: _fmt(_eAmpm, _eHour, _eMinIdx),
                    active: !isStart,
                    onTap: () => _switchTab(1),
                    nextDay: _to24(_eAmpm, _eHour) * 60 + _eMinIdx * _minStep <=
                        _to24(_sAmpm, _sHour) * 60 + _sMinIdx * _minStep,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // ── 총 시간 표시 ───────────────────────────
            Text(
              '총 $totalStr',
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF7C3AED),
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // ── 피커 (탭 전환 시 key로 재생성) ──────────
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F8FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // 오전/오후
                    Expanded(
                      flex: 3,
                      child: CupertinoPicker(
                        key: ValueKey('ampm-$_tab'),
                        scrollController: _ampmCtrl,
                        itemExtent: 50,
                        selectionOverlay: const _PickerOverlay(),
                        onSelectedItemChanged: (i) {
                          setState(() {
                            if (isStart)
                              _sAmpm = i;
                            else
                              _eAmpm = i;
                          });
                        },
                        children: ['오전', '오후']
                            .map((t) => Center(
                                  child: Text(t,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                      ),
                    ),
                    // 시
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        key: ValueKey('hour-$_tab'),
                        scrollController: _hourCtrl,
                        itemExtent: 50,
                        looping: true,
                        selectionOverlay:
                            const CupertinoPickerDefaultSelectionOverlay(
                          capStartEdge: false,
                          capEndEdge: false,
                        ),
                        onSelectedItemChanged: (i) {
                          setState(() {
                            if (isStart)
                              _sHour = i + 1;
                            else
                              _eHour = i + 1;
                          });
                        },
                        children: List.generate(
                            12,
                            (i) => Center(
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700)),
                                )),
                      ),
                    ),
                    // :
                    const Text(':',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827))),
                    // 분
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        key: ValueKey('min-$_tab'),
                        scrollController: _minCtrl,
                        itemExtent: 50,
                        looping: true,
                        selectionOverlay: const _PickerOverlay(capStart: false),
                        onSelectedItemChanged: (i) {
                          setState(() {
                            if (isStart)
                              _sMinIdx = i;
                            else
                              _eMinIdx = i;
                          });
                        },
                        children: List.generate(
                            _minCount,
                            (i) => Center(
                                  child: Text(
                                      (i * _minStep).toString().padLeft(2, '0'),
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700)),
                                )),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.time,
    required this.active,
    required this.onTap,
    this.nextDay = false,
  });
  final String label;
  final String time;
  final bool active;
  final VoidCallback onTap;
  final bool nextDay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7C3AED) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active
                    ? Colors.white.withOpacity(0.8)
                    : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    time,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                if (nextDay)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withOpacity(0.25)
                          : const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+1',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : const Color(0xFF7C3AED),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerOverlay extends StatelessWidget {
  const _PickerOverlay({this.capStart = true});
  final bool capStart;

  @override
  Widget build(BuildContext context) {
    return CupertinoPickerDefaultSelectionOverlay(
      capStartEdge: capStart,
      capEndEdge: false,
    );
  }
}
