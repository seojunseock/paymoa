// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';
import '../payroll/payroll.dart';
import 'work_editor_args.dart' as wargs;

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
    this.wageAt, // ★ 날짜별 시급 리졸버(선택)
  });

  final VoidCallback onBack; // (미사용: 상단바 제거)
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
  late DateTime ym; // 현재 월(1일 기준)
  Set<String> activeIds = {}; // 표시 중인 알바 ID

  @override
  void initState() {
    super.initState();
    ym = DateTime(DateTime.now().year, DateTime.now().month, 1);
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

  @override
  Widget build(BuildContext context) {
    // 상단 합계(활성 알바만)
    int netSum = 0;
    for (final aid in activeIds) {
      final alba = widget.albas.firstWhere(
        (a) => a.id == aid,
        orElse: () => UICalendarAlba(id: aid, name: '', colorHex: '#3B82F6', hourlyWage: 0),
      );
      final tax = widget.getTaxPolicy(aid) ?? TaxConfig.none;
      final ins = widget.getInsurancePolicy(aid) ?? const InsuranceNone();
      final pol = widget.getSurchargePolicy(aid) ?? const SurchargePolicy();
      final monthSchedules = widget.schedules
          .where((s) => s.albaId == aid && s.year == ym.year && s.month == ym.month)
          .toList();

      final summary = computeMonthlySummary(
        alba: alba,
        ymYear: ym.year,
        ymMonth: ym.month,
        schedules: monthSchedules,
        tax: tax,
        insurance: ins,
        policy: pol,
        // ★ 날짜별 시급 사용
        wageAt: widget.wageAt,
      );
      netSum += summary.net;
    }

    return SafeArea(
      child: Column(
        children: [
          // 월 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '이전 달',
                  onPressed: () => setState(() => ym = DateTime(ym.year, ym.month - 1, 1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${ym.year}년 ${ym.month}월',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '다음 달',
                  onPressed: () => setState(() => ym = DateTime(ym.year, ym.month + 1, 1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          // 합계
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Text('급여:'),
                const SizedBox(width: 8),
                Text('${_comma(netSum)}원', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),

          // 알바 필터칩
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

          const SizedBox(height: 8),

          // 달력
          Expanded(
            child: _CalendarGrid(
              ym: ym,
              albas: widget.albas,
              schedules: widget.schedules,
              activeIds: activeIds,
              onTapDay: (day, schedulesOfDay) {
                final date = DateTime(ym.year, ym.month, day);

                if (schedulesOfDay.isEmpty) {
                  widget.openWorkEditor(
                    wargs.WorkEditorArgs(
                      mode: wargs.WorkEditorArgsMode.add,
                      presetDate: date,
                    ),
                  );
                } else {
                  final s = schedulesOfDay.first;
                  widget.openWorkEditor(
                    wargs.WorkEditorArgs(
                      mode: wargs.WorkEditorArgsMode.edit,
                      scheduleId: s.id,
                      presetDate: date, // 타이틀/추가 기본 날짜 유지
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
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
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.ym,
    required this.albas,
    required this.schedules,
    required this.activeIds,
    required this.onTapDay,
  });

  final DateTime ym;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final Set<String> activeIds;
  final void Function(int day, List<UICalendarSchedule> schedulesOfDay) onTapDay;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(ym.year, ym.month, 1).weekday % 7; // 일=0
    final daysInMonth = DateTime(ym.year, ym.month + 1, 0).day;

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final daySchedules = schedules
          .where((s) =>
              s.year == ym.year &&
              s.month == ym.month &&
              s.day == d &&
              activeIds.contains(s.albaId))
          .toList()
        ..sort((a, b) => (a.startHour * 60 + a.startMinute)
            .compareTo(b.startHour * 60 + b.startMinute));

      cells.add(_DayCell(
        day: d,
        items: daySchedules.map((s) {
          final alba = albas.firstWhere(
            (a) => a.id == s.albaId,
            orElse: () => UICalendarAlba(id: s.albaId, name: '', colorHex: '#3B82F6', hourlyWage: 0),
          );
          return _CellItem(s: s, alba: alba);
        }).toList(),
        onTap: () => onTapDay(d, daySchedules),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Row(
            children: const [
              _DowLabel('일', isSun: true),
              _DowLabel('월'),
              _DowLabel('화'),
              _DowLabel('수'),
              _DowLabel('목'),
              _DowLabel('금'),
              _DowLabel('토', isSat: true),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: cells.length,
              itemBuilder: (_, i) => cells[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _CellItem {
  final UICalendarSchedule s;
  final UICalendarAlba alba;
  _CellItem({required this.s, required this.alba});
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.items, required this.onTap});
  final int day;
  final List<_CellItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '$day',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),

            // 스케줄 바: 최대 2개, 초과는 +N
            ...items.take(2).map((it) {
              final s = it.s;
              final color = _parseColor(it.alba.colorHex);
              final onColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

              final label =
                  '${_hh(s.startHour)}–${_hh(s.endHour)} (${_hoursText(_workedMinutes(s))})';

              return Container(
                height: 18,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: onColor,
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            if (items.length > 2)
              Text(
                '+${items.length - 2}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.right,
              ),
          ],
        ),
      ),
    );
  }

  static String _hh(int h) => h.toString().padLeft(2, '0');

  static int _workedMinutes(UICalendarSchedule s) {
    final start = Duration(hours: s.startHour, minutes: s.startMinute);
    var end = Duration(hours: s.endHour, minutes: s.endMinute);
    var diff = end - start;
    if (diff.isNegative) diff += const Duration(days: 1);
    final worked = diff.inMinutes - (s.breakMinutes).clamp(0, diff.inMinutes);
    return worked.clamp(0, 24 * 60);
  }

  static String _hoursText(int minutes) {
    final h = minutes / 60.0;
    final intH = h.floor();
    final isInt = (h - intH).abs() < 0.001;
    return isInt ? '$intH시간' : '${h.toStringAsFixed(1)}시간';
  }

  static Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16) ?? 0x3B82F6;
    return Color(0xFF000000 | v);
  }
}

class _DowLabel extends StatelessWidget {
  const _DowLabel(this.text, {this.isSun = false, this.isSat = false});
  final String text;
  final bool isSun;
  final bool isSat;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? c;
    if (isSun) c = Colors.redAccent;
    if (isSat) c = Colors.blueAccent;
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: c ?? theme.colorScheme.onSurface.withOpacity(0.7)),
        ),
      ),
    );
  }
}
