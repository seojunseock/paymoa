// lib/screens/alba_start_screen.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../common/app_words.dart';
import '../common/korean_holidays.dart';
import '../common/paymoa_design.dart';
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

String _fmtMultiplier(double v) {
  if (v == v.truncateToDouble()) return '${v.toInt()}.0';
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

String _wonNum(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    b.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && left % 3 == 0) b.write(',');
  }
  return b.toString();
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

/* ───────────────────────── Paymoa UI 컴포넌트 ───────────────────────── */

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
    return PmCard(
      accent: accent,
      padding: padding,
      child: child,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.text,
    required this.selected,
    required this.isToday,
    this.weekday,
    this.isHoliday = false,
  });

  final String text;
  final bool selected;
  final bool isToday;
  final int? weekday; // DateTime.monday(1) ~ DateTime.sunday(7)
  final bool isHoliday;

  @override
  Widget build(BuildContext context) {
    final isSun = weekday == DateTime.sunday;
    final isSat = weekday == DateTime.saturday;

    final bg = selected
        ? PaymoaColors.primary
        : isToday
            ? PaymoaColors.primary.withOpacity(0.08)
            : Colors.transparent;

    final fg = selected
        ? Colors.white
        : isToday
            ? PaymoaColors.primary
            : (isSun || isHoliday)
                ? const Color(0xFFE53935)
                : isSat
                    ? const Color(0xFF1E88E5)
                    : PaymoaColors.textPrimary;

    final border = (!selected && isToday)
        ? Border.all(color: PaymoaColors.primary.withOpacity(0.3), width: 1.5)
        : null;

    return Center(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
    this.wageAt,
  });

  final UICalendarAlba alba;
  final Color color;
  final _MergedBlock block;
  final DateTime localDate;

  final void Function(String scheduleId) onEdit;
  final void Function(String scheduleId) onDelete;
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
    final effectiveWage = b.children.map((s) {
      final base = s.overrideHourlyWage ??
          widget.wageAt?.call(widget.alba.id, widget.localDate) ??
          widget.alba.hourlyWage;
      return (base * s.wageMultiplier).round();
    }).reduce((a, b) => a > b ? a : b);

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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PaymoaColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                // ── 시급 배지
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: widget.color.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${_wonNum(effectiveWage)}원/시',
                    style: TextStyle(
                      fontSize: 11,
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
                      child: Row(
                        children: [
                          Text(
                            '${_timeRangeText(s.startHour, s.startMinute, s.endHour, s.endMinute)}  ·  ${_workTypeLabel(s.workType)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.70),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (s.wageMultiplier != 1.0)
                            _SurchargeBadge(
                              label: '보너스 ${_fmtMultiplier(s.wageMultiplier)}',
                              color: widget.color,
                            ),
                        ],
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
                      title: Row(
                        children: [
                          Text(
                            '$st~$et (${_workTypeLabel(s.workType)})',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (s.wageMultiplier != 1.0)
                            _SurchargeBadge(
                              label: '보너스 ${_fmtMultiplier(s.wageMultiplier)}',
                              color: widget.color,
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: AppWords.delete,
                            icon: const Icon(Icons.delete_outline,
                                color: PaymoaColors.error),
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
    this.getSurchargeAt,
    this.getTaxAt,
    this.getInsuranceAt,
    this.getPayrollPolicy,
    this.getWageAt,
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

  /// ✅ 날짜별 가산정책 콜백 (정책 이력 반영)
  final pol.SurchargePolicy Function(DateTime)? Function(String albaId)?
      getSurchargeAt;
  final pol.TaxConfig Function(DateTime)? Function(String albaId)? getTaxAt;
  final pol.InsuranceConfig Function(DateTime)? Function(String albaId)?
      getInsuranceAt;
  final PayrollPolicy? Function(String albaId)? getPayrollPolicy;
  // ✅ 날짜별 시급 조회 (policyHistory 기반)
  final int Function(String albaId, DateTime dateLocal)? getWageAt;

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
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(AppWords.delete,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
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
        const SnackBar(content: Text('오류가 발생했어요. 잠시 후 다시 시도해 주세요.')),
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
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(AppWords.delete,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
            ),
          ],
        );
      },
    );

    if (ok == true) widget.onDeleteAlba(albaId);
  }

  /// ✅ 매장 탈퇴 확인 다이얼로그 (조인 알바 전용)
  Future<void> _confirmLeaveStore(String storeId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: const Text('매장 탈퇴'),
          content: const Text(
            '이 매장에서 탈퇴하면 매장 근무 기록이 더 이상 표시되지 않아요.\n계속할까요?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text(AppWords.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text(
                '탈퇴',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFF43F5E)),
              ),
            ),
          ],
        );
      },
    );

    if (ok == true) widget.onDeleteAlba(storeId);
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

    // ① 코드 입력 시트 (bottom sheet)
    final sheet = await showModalBottomSheet<JoinStoreSheetResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const JoinStoreSheet(),
    );
    if (!mounted || sheet == null) return;

    // ② 중간 시트 없이 바로 AlbaFormScreen으로
    //    - 이름 입력, 매장 별칭, 근무설정 모두 한 화면에서
    final i0 = sheet.initial;
    final initial = AlbaFormInitial(
      storeId: i0.storeId,
      workerName: '', // AlbaFormScreen에서 직접 입력
      storeName: i0.storeName, // 매장 기본명 (별칭으로 변경 가능)
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
      inheritFromStore: true, // 신규 조인: 항상 매장 설정 따름
      storeDefaults: i0.storeDefaults,
    );

    final form = await Navigator.push<AlbaFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AlbaFormScreen(
          existingSchedules: widget.schedules,
          initial: initial,
          editingAlbaId: null,
          onBack: () => Navigator.pop(context),
          onSubmit: (r) async => Navigator.pop(context, r),
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
        form.workerName ?? '', // AlbaFormScreen에서 입력한 이름
        form.storeName, // 별칭
        form,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.done)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오류가 발생했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _joinSaving = false);
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
                  wageAt: _wageAtFn,
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
                    final nav = Navigator.of(ctx);
                    await _safeDeleteSchedule(ctx, scheduleId);
                    if (mounted && nav.canPop()) nav.pop();
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
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ...cards,
                // ✅ 하단 근무 추가 버튼 (캘린더 화면과 동일)
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onOpenWorkEditor(
                          wargs.WorkEditorArgs(
                            mode: wargs.WorkEditorArgsMode.add,
                            presetDate: localDate,
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('근무 추가',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
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

  pol.SurchargePolicy Function(DateTime)? _surchargeAtOf(String id) =>
      widget.getSurchargeAt?.call(id);

  pol.TaxConfig Function(DateTime)? _taxAtOf(String id) =>
      widget.getTaxAt?.call(id);

  pol.InsuranceConfig Function(DateTime)? _insAtOf(String id) =>
      widget.getInsuranceAt?.call(id);

  PayrollPolicy? _payrollOf(String id) => widget.getPayrollPolicy?.call(id);

  /// ✅ 날짜별 시급 조회 (policyHistory 기반)
  int Function(String albaId, DateTime dateLocal)? get _wageAtFn =>
      widget.getWageAt;

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

  // ────────────────────────────────────────────────
  // 급여 계산: 급여 정책 기반 현재 기간 전체 예상 급여
  // ────────────────────────────────────────────────

  /// 급여 라벨 반환 ("2월 급여" 또는 "2/15~3/14 급여")
  String _payLabel(String albaId) {
    final payroll = _payrollOf(albaId);
    if (payroll == null || payroll.cycle == PayCycleType.monthly) {
      return '${_focusedDay.month}월 급여';
    }
    if (payroll.cycle == PayCycleType.daily) {
      return '오늘 급여';
    }
    final preview = computePreviewForDate(
      policy: payroll,
      anyDateInPeriod: _focusedDay,
    );
    final s = preview.period.start;
    final e = preview.period.end;
    return '${s.month}/${s.day}~${e.month}/${e.day} 급여';
  }

  /// 특정 월(ymDate)의 세후 예상 수령액 계산
  int _calcPeriodNetForMonth(UICalendarAlba alba, DateTime ymDate) {
    final payroll = _payrollOf(alba.id);
    final sur = _surOf(alba.id) ?? const pol.SurchargePolicy();

    // ── ① 달력 월(1일~말일) 기준 ──────────────────────
    final isCalendarMonth = payroll == null ||
        (payroll.cycle == PayCycleType.monthly &&
            (payroll.monthlyStartDay ?? 1) == 1);

    if (isCalendarMonth) {
      final allAlbaSchedules =
          widget.schedules.where((s) => s.albaId == alba.id).toList();
      final monthSchedules = allAlbaSchedules
          .where((s) => s.year == ymDate.year && s.month == ymDate.month)
          .toList();
      if (monthSchedules.isEmpty) return 0;
      final surchargeAt = _surchargeAtOf(alba.id);
      final monthStart = DateTime(ymDate.year, ymDate.month, 1);
      final result = computeMonthlySummary(
        alba: alba,
        ymDate: ymDate,
        schedules: monthSchedules,
        allSchedules: allAlbaSchedules,
        tax: _taxAtOf(alba.id)?.call(monthStart) ?? _taxOf(alba.id),
        insurance: _insAtOf(alba.id)?.call(monthStart) ?? _insOf(alba.id),
        policy: sur,
        surchargeAt: surchargeAt,
        wageAt: _wageAtFn,
      );
      return result.net;
    }

    // ── ② 급여 기간 기준 (앵커 월·주·2주·커스텀) ────────────
    final surchargeAt2 = _surchargeAtOf(alba.id);
    final summary = const PayrollEngine().summaryForDate(
      policy: payroll,
      alba: alba,
      schedules: widget.schedules.where((s) => s.albaId == alba.id).toList(),
      tax: _taxOf(alba.id),
      insurance: _insOf(alba.id),
      surchargePolicy: sur,
      wageAt: _wageAtFn,
      surchargeAt: surchargeAt2,
      taxAt: _taxAtOf(alba.id),
      insuranceAt: _insAtOf(alba.id),
      anyDateInPeriod: ymDate,
    );
    return summary.net;
  }

  /// 현재 포커스 월의 세후 예상 수령액 계산
  int _calcPeriodNet(UICalendarAlba alba) =>
      _calcPeriodNetForMonth(alba, _focusedDay);

  /// 다음 급여일 계산
  DateTime? _nextPayDate(UICalendarAlba alba) {
    final payroll = _payrollOf(alba.id);
    if (payroll == null) return null;
    final preview = computePreviewForDate(
      policy: payroll,
      anyDateInPeriod: DateTime.now(),
    );
    return preview.payDate;
  }

  /// D-day 텍스트 (D-7, D-Day, D+1 …)
  String _dDayText(DateTime payDate) {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final target = DateTime(payDate.year, payDate.month, payDate.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'D-Day';
    if (diff > 0) return 'D-$diff';
    return 'D+${-diff}';
  }

  int _totalWorkDaysOfMonth(String albaId) {
    final y = _focusedDay.year;
    final m = _focusedDay.month;
    return widget.schedules
        .where((s) => s.albaId == albaId && s.year == y && s.month == m)
        .length;
  }

  // ─── 오늘 근무 목록 (시작 시간 순) ────────────────────────────
  List<({UICalendarSchedule s, UICalendarAlba alba})> _todaySchedules() {
    final now = DateTime.now();
    final todayItems = <({UICalendarSchedule s, UICalendarAlba alba})>[];

    for (final s in widget.schedules) {
      if (s.year != now.year || s.month != now.month || s.day != now.day)
        continue;
      final alba = widget.albas.firstWhere(
        (a) => a.id == s.albaId,
        orElse: () => UICalendarAlba(
          id: s.albaId,
          name: '?',
          colorHex: '#9CA3AF',
          hourlyWage: 0,
          payDay: 25,
        ),
      );
      todayItems.add((s: s, alba: alba));
    }

    todayItems.sort((a, b) {
      final am = a.s.startHour * 60 + a.s.startMinute;
      final bm = b.s.startHour * 60 + b.s.startMinute;
      return am.compareTo(bm);
    });
    return todayItems;
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
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        automaticallyImplyLeading: false, // ✅ 바텀탭 있으므로 뒤로가기 불필요
        title: const Text(
          '페이모아',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: PaymoaColors.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _joinSaving ? null : _showFabMenu,
        backgroundColor: PaymoaColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: _joinSaving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
        label: Text(
          _joinSaving ? '잠깐만요...' : '추가',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WeeklyCalendarBox(
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  onDaySelected: _onTapDay,
                  onPageChanged: (fd) => setState(() => _focusedDay = fd),
                  eventLoader: (day) {
                    final k = DateTime(day.year, day.month, day.day);
                    return _dotsByDay[k] ?? const <_DotEvent>[];
                  },
                  albas: widget.albas,
                ),
              ],
            ),
          ),
          // ─── 오늘 근무 한줄 요약 ────────────────────────────────
          Builder(builder: (ctx) {
            final todayItems = _todaySchedules();
            if (todayItems.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _TodayWorkBanner(items: todayItems),
            );
          }),
          Expanded(
            child: widget.albas.isEmpty
                ? const _EmptyView()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: widget.albas.length,
                    itemBuilder: (context, index) {
                      final alba = widget.albas[index];
                      final color = cp.parseColor(alba.colorHex);

                      final workCount = _totalWorkDaysOfMonth(alba.id);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: _TossCard(
                          accent: color,
                          child: Theme(
                            data: theme.copyWith(
                                dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: PageStorageKey(alba.id),
                              tilePadding:
                                  const EdgeInsets.fromLTRB(0, 4, 4, 4),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(0, 8, 0, 12),
                              // 펼치기 아이콘 Paymoa 보라
                              iconColor: PaymoaColors.primary,
                              collapsedIconColor: PaymoaColors.textTertiary,
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 알바 이름
                                  Text(
                                    alba.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: PaymoaColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // 시급 (날짜 기반: 사장님이 설정한 적용일 반영)
                                  Text(
                                    '시급 ${_won(widget.getWageAt?.call(alba.id, DateTime.now()) ?? alba.hourlyWage)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: PaymoaColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                // 구분선
                                Divider(
                                  height: 1,
                                  color: color.withOpacity(0.2),
                                ),
                                const SizedBox(height: 10),
                                _kv(
                                  '${_focusedDay.month}${AppWords.monthUnit} ${AppWords.workCount}',
                                  '$workCount${AppWords.timesUnit}',
                                ),
                                // ── 다음 급여일 D-day
                                () {
                                  final payDate = _nextPayDate(alba);
                                  if (payDate == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final dday = _dDayText(payDate);
                                  final ddayColor = dday.startsWith('D+')
                                      ? PaymoaColors.textSecondary
                                      : color;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '다음 급여일',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: PaymoaColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${payDate.month}/${payDate.day}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: PaymoaColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: ddayColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            dday,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: ddayColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }(),
                                // ── 이번달 예상 급여
                                _kv(
                                  '이번 ${_focusedDay.month}월 예상 수령',
                                  _won(_calcPeriodNet(alba)),
                                ),
                                const SizedBox(height: 12),
                                // ✅ 매장 조인 알바 vs 개인 알바 버튼 분기
                                if (alba.storeId.isNotEmpty) ...[
                                  // ─────────────────────────────────────
                                  // 📦 매장 조인: 시급/정책은 사장님 관리
                                  // 버튼: 탈퇴 | 근무 추가
                                  // ─────────────────────────────────────
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F0FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.storefront_outlined,
                                            size: 13,
                                            color: PaymoaColors.primary
                                                .withValues(alpha: 0.7)),
                                        const SizedBox(width: 5),
                                        const Text(
                                          '시급·정책은 사장님이 설정해요',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF6D28D9),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 40,
                                    child: Row(
                                      children: [
                                        // ① 탈퇴: 빨강
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _confirmLeaveStore(alba.id),
                                            icon: const Icon(
                                              Icons.logout_rounded,
                                              size: 16,
                                              color: PaymoaColors.error,
                                            ),
                                            label: const Text(
                                              '탈퇴',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: PaymoaColors.error,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 1,
                                            height: 24,
                                            child: ColoredBox(
                                                color: Color(0xFFD1D5DB))),
                                        // ② 근무 추가: 보라
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                widget.onOpenWorkEditor(
                                              wargs.WorkEditorArgs(
                                                mode: wargs
                                                    .WorkEditorArgsMode.add,
                                                preselectedAlbaId: alba.id,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.add,
                                              size: 16,
                                              color: PaymoaColors.primary,
                                            ),
                                            label: const Text(
                                              '근무 추가',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: PaymoaColors.primary,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  PaymoaColors.primary,
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  // ─────────────────────────────────────
                                  // 👤 개인 알바: 삭제 / 수정 / 근무 추가
                                  // ─────────────────────────────────────
                                  SizedBox(
                                    height: 40,
                                    child: Row(
                                      children: [
                                        // ① 삭제: 빨강
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _confirmDeleteAlba(alba.id),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: PaymoaColors.error,
                                            ),
                                            label: const Text(
                                              '삭제',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: PaymoaColors.error,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 1,
                                            height: 24,
                                            child: ColoredBox(
                                                color: Color(0xFFD1D5DB))),
                                        // ② 수정: 회색
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                widget.onEditAlba(alba.id),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: PaymoaColors.primary,
                                            ),
                                            label: const Text(
                                              '수정',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: PaymoaColors.primary,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  PaymoaColors.primary,
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 1,
                                            height: 24,
                                            child: ColoredBox(
                                                color: Color(0xFFD1D5DB))),
                                        // ③ 근무 추가: 보라
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                widget.onOpenWorkEditor(
                                              wargs.WorkEditorArgs(
                                                mode: wargs
                                                    .WorkEditorArgsMode.add,
                                                preselectedAlbaId: alba.id,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.add,
                                              size: 16,
                                              color: PaymoaColors.primary,
                                            ),
                                            label: const Text(
                                              '근무 추가',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: PaymoaColors.primary,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  PaymoaColors.primary,
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
    required this.albas,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final List<dynamic> Function(DateTime day) eventLoader;
  final List<UICalendarAlba> albas;

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.05),
            blurRadius: 0,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
            weekday: day.weekday,
            isHoliday: day.weekday != DateTime.sunday &&
                KoreanHolidays.isHoliday(day),
          ),
          todayBuilder: (ctx, day, _) => _DayCell(
            text: '${day.day}',
            selected: false,
            isToday: true,
            weekday: day.weekday,
            isHoliday: day.weekday != DateTime.sunday &&
                KoreanHolidays.isHoliday(day),
          ),
          selectedBuilder: (ctx, day, _) => _DayCell(
            text: '${day.day}',
            selected: true,
            isToday: false,
            weekday: day.weekday,
            isHoliday: day.weekday != DateTime.sunday &&
                KoreanHolidays.isHoliday(day),
          ),
          markerBuilder: (context, day, events) {
            final dots = events.whereType<_DotEvent>().toList();

            if (dots.isEmpty) return const SizedBox.shrink();

            const double dotSize = 6;
            const double dotGap = 4;

            return Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(dots.length.clamp(0, 4), (i) {
                  return Container(
                    width: dotSize,
                    height: dotSize,
                    margin: EdgeInsets.only(
                      right: i == dots.length - 1 ? 0 : dotGap,
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
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 14,
              color: PaymoaColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          v,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: PaymoaColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/* ───────────────────────── 오늘 근무 요약 배너 ───────────────────────── */

class _TodayWorkBanner extends StatelessWidget {
  const _TodayWorkBanner({required this.items});

  final List<({UICalendarSchedule s, UICalendarAlba alba})> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        // 오늘 강조 - 연보라 배경
        color: PaymoaColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: PaymoaColors.primary.withOpacity(0.18),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 📅 오늘 라벨
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: PaymoaColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              '오늘',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 근무 목록 (가로 스크롤)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final color = cp.parseColor(item.alba.colorHex);
                  final start = _fmtHm(item.s.startHour, item.s.startMinute);
                  final end = _fmtHm(item.s.endHour, item.s.endMinute);
                  final isNext = (item.s.endHour * 60 + item.s.endMinute) <=
                      (item.s.startHour * 60 + item.s.startMinute);

                  return Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 알바 색상 점
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        // "알바명 09:00~18:00"
                        Text(
                          '${item.alba.name}  $start~$end${isNext ? '(익일)' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PaymoaColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 구분선 (마지막 아이템 제외)
                        if (i < items.length - 1) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: 14,
                            color: PaymoaColors.textTertiary.withOpacity(0.4),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: PaymoaColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.work_outline,
                size: 64,
                color: PaymoaColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '아직 등록된 알바가 없어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: PaymoaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '오른쪽 아래 + 버튼을 눌러\n알바를 추가하거나 매장에 입장해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: PaymoaColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurchargeBadge extends StatelessWidget {
  const _SurchargeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}


//1. 터미널 열기
//  키보드에서 ⌘(Command) + Space 동시에 누르기
//  → 검색창에 terminal 입력
//  → Enter

//2. git clone

// git clone https://github.com/seojunseock/paymoa.git
//  → 완료되면:
//  cd paymoa

//  3. 패키지 설치

//  flutter pub get
//  → 완료되면:
//  cd ios && pod install && cd ..
//  시간 걸림. 완료까지 기다리기.

//  4. Claude Code 설치

//  npm install -g @anthropic-ai/claude-code

//  5. Claude Code 실행

// claude
//  → 로그인 화면 뜨면 Anthropic 계정으로 로그인
//  → 켜지면 입력:
//"MAC_SESSION_GUIDE.md 읽고 브리핑해줘"  