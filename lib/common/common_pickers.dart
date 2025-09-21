// lib/common/common_pickers.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // PointerScrollEvent

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
 *  - 상단: 취소 / 제목 / 완료 (가로)
 *  - 하단: 현재 선택 프리뷰 (실시간 갱신, 중앙 정렬)
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
                  sAp = ap; sH12 = h; sMin = m;
                  setState(() {});
                }

                void onEndChange(int ap, int h, int m) {
                  eAp = ap; eH12 = h; eMin = m;
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
                        Text('근무시간', style: Theme.of(ctx).textTheme.titleMedium),
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
                              Text('시작', style: Theme.of(ctx).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              _TimeSection12h(
                                ap: sAp, h12: sH12, min: sMin,
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
                              Text('종료', style: Theme.of(ctx).textTheme.labelLarge),
                              const SizedBox(height: 8),
                              _TimeSection12h(
                                ap: eAp, h12: eH12, min: eMin,
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

  final int ap;   // 0=오전, 1=오후
  final int h12;  // 1..12
  final int min;  // 0..59
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
    _hCtrl  = FixedExtentScrollController(initialItem: _h12 - 1);
    _mCtrl  = FixedExtentScrollController(initialItem: _m);
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
          onChanged: (i) { setState(() => _ap = i); widget.onChange(_ap, _h12, _m); },
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _Wheel(
            itemExtent: _itemExtent,
            controller: _hCtrl,
            count: 12,
            initialIndex: _h12 - 1,
            display: (i) => (i + 1).toString().padLeft(2, '0'),
            onChanged: (i) { setState(() => _h12 = i + 1); widget.onChange(_ap, _h12, _m); },
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
            onChanged: (i) { setState(() => _m = i); widget.onChange(_ap, _h12, _m); },
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
    widget.controller.animateToItem(
      _current,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
    ).whenComplete(() {
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
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
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

    if (widget.width != null) return SizedBox(width: widget.width, child: interactive);
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
                        Text('휴게 시간', style: Theme.of(ctx).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: () { onDone(cur); Navigator.of(ctx).pop(); },
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
                          ..selection = TextSelection.collapsed(offset: customText.length),
                        onChanged: (s) {
                          final v = int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                          cur = v.clamp(0, 600);
                          customText = cur == 0 ? '' : cur.toString();
                        },
                      ),

                    const SizedBox(height: 12),
                    Text('선택: ${cur}분',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
 * 급여일 시트 (실시간 미리보기 업데이트)
 *  - 상단: 취소 / 제목 / 완료 (가로)
 *  - 하단: "매월 N일" 중앙 정렬, 휠 움직일 때 즉시 갱신
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
                          onPressed: () { onDone(cur); Navigator.of(ctx).pop(); },
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
                        onSelectedItemChanged: (i) => setState(() => cur = i + 1),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 31,
                          builder: (_, i) => Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx).colorScheme.surfaceVariant.withOpacity(0.5),
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
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
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
