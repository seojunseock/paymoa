// lib/screens/date_assign_sheet.dart
import 'package:flutter/material.dart';

class DateAssignResult {
  final Set<DateTime> selectedDates; // UTC 00:00
  const DateAssignResult(this.selectedDates);
}

/// 근무 날짜 선택 시트(달력)
Future<DateAssignResult?> showDateAssignSheet(
  BuildContext context, {
  required Set<DateTime> existing, // UTC 00:00 날짜들
  required bool Function(DateTime dateUtc) checkConflict,
}) {
  final now = DateTime.now();
  final initialYm = DateTime(now.year, now.month, 1);

  return showDialog<DateAssignResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _DateAssignDialog(
      initialYm: initialYm,
      initialSelected: existing.map(_utcMid).toSet(),
      checkConflict: checkConflict,
    ),
  );
}

DateTime _utcMid(DateTime d) => DateTime.utc(d.year, d.month, d.day);

class _DateAssignDialog extends StatefulWidget {
  const _DateAssignDialog({
    required this.initialYm,
    required this.initialSelected,
    required this.checkConflict,
  });

  final DateTime initialYm; // 로컬 기준 1일
  final Set<DateTime> initialSelected; // UTC 00:00
  final bool Function(DateTime) checkConflict;

  @override
  State<_DateAssignDialog> createState() => _DateAssignDialogState();
}

class _DateAssignDialogState extends State<_DateAssignDialog> {
  late DateTime ym;
  late Set<DateTime> selected; // UTC 00:00

  @override
  void initState() {
    super.initState();
    ym = widget.initialYm;
    selected = {...widget.initialSelected};
  }

  bool _isConflict(DateTime dUtc) => widget.checkConflict(dUtc);

  void _toggle(DateTime dUtc) {
    setState(() {
      if (selected.contains(dUtc)) {
        selected.remove(dUtc);
      } else {
        selected.add(dUtc);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Row(
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
                      style: theme.textTheme.titleMedium,
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
            const SizedBox(height: 6),

            // 요일 헤더
            Row(
              children: const [
                _Dow('일', sun: true),
                _Dow('월'),
                _Dow('화'),
                _Dow('수'),
                _Dow('목'),
                _Dow('금'),
                _Dow('토', sat: true),
              ],
            ),
            const SizedBox(height: 6),

            // 날짜 그리드(현재 월만)
            _MonthGrid(
              ym: ym,
              isSelected: (dLocal) => selected.contains(_utcMid(dLocal)),
              hasConflict: (dLocal) => _isConflict(_utcMid(dLocal)),
              onTap: (dLocal) => _toggle(_utcMid(dLocal)),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // 하단 액션
            Row(
              children: [
                Text('선택: ${selected.length}일'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(DateAssignResult(selected)),
                  child: const Text('적용'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dow extends StatelessWidget {
  const _Dow(this.text, {this.sun = false, this.sat = false});
  final String text;
  final bool sun;
  final bool sat;

  @override
  Widget build(BuildContext context) {
    final c = sun
        ? Colors.redAccent
        : sat
            ? Colors.blueAccent
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.ym,
    required this.isSelected,
    required this.hasConflict,
    required this.onTap,
  });

  final DateTime ym; // 로컬 1일
  final bool Function(DateTime dLocal) isSelected;
  final bool Function(DateTime dLocal) hasConflict;
  final void Function(DateTime dLocal) onTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(ym.year, ym.month, 1);
    final daysInMonth = DateTime(ym.year, ym.month + 1, 0).day;
    final firstWeekday = first.weekday % 7; // 일=0

    final cells = <Widget>[];

    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final dateLocal = DateTime(ym.year, ym.month, d);
      final selected = isSelected(dateLocal);
      final conflict = hasConflict(dateLocal);

      cells.add(_DateCell(
        day: d,
        selected: selected,
        hasConflict: conflict,
        onTap: () => onTap(dateLocal),
      ));
    }

    return SizedBox(
      height: 6 * 56, // 6주 그리드가 폰 화면에 딱 들어오도록
      child: GridView.count(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: cells,
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.day,
    required this.selected,
    required this.hasConflict,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool hasConflict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selBg = theme.colorScheme.primary;
    final selFg = theme.colorScheme.onPrimary;
    final normalBg = theme.colorScheme.surfaceVariant.withOpacity(0.35);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? selBg : normalBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? selBg : theme.dividerColor),
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            // 날짜 숫자 중앙 정렬
            Center(
              child: Text(
                '$day',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: selected ? selFg : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (hasConflict)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
