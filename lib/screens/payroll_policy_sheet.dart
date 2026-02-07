// lib/screens/payroll_policy_sheet.dart
import 'package:flutter/material.dart';

import '../common/app_words.dart';
import '../payroll/payroll.dart';

Future<PayrollPolicy?> showPayrollPolicySheet({
  required BuildContext context,
  required PayrollPolicy initial,
  required PayrollViewerRole role,
}) {
  return showModalBottomSheet<PayrollPolicy>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return _PayrollPolicySheet(
        role: role,
        initialPolicy: initial,
      );
    },
  );
}

/// ✅ 우리가 확정한 3정책만 노출
/// 1) 한 달(1일~말일)로 묶기
/// 2) 매달 같은 날 기준으로 묶기 (예: 16일~다음달 15일)
/// 3) 하루씩 따로 계산하기(일급)
enum _MvpPayrollKind {
  calendarMonth,
  anchorMonth,
  shortTermDaily,
}

class _PayrollPolicySheet extends StatefulWidget {
  const _PayrollPolicySheet({
    required this.role,
    required this.initialPolicy,
  });

  final PayrollViewerRole role;
  final PayrollPolicy initialPolicy;

  @override
  State<_PayrollPolicySheet> createState() => _PayrollPolicySheetState();
}

class _PayrollPolicySheetState extends State<_PayrollPolicySheet> {
  final _engine = const PayrollEngine();
  int _step = 0;

  late PayrollPolicy _policy;

  // step2: 마감 후 N일
  final _afterDaysCtrl = TextEditingController(text: '0');

  // step1: 3정책 선택
  late _MvpPayrollKind _kind;

  @override
  void initState() {
    super.initState();

    _policy = _normalizeToMvp(widget.initialPolicy);
    _kind = _kindFromPolicy(_policy);

    if (_policy.payRule.type == PayDateRuleType.afterEndPlusDays) {
      _afterDaysCtrl.text = '${_policy.payRule.plusDays ?? 0}';
    } else {
      _afterDaysCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _afterDaysCtrl.dispose();
    super.dispose();
  }

  List<PeriodPayPreview> get _previews =>
      _engine.previewNext(policy: _policy, count: 3);

  PayrollPolicy _normalizeToMvp(PayrollPolicy p) {
    final now = _dateOnly(DateTime.now());

    // 일급이면 그대로
    if (p.cycle == PayCycleType.daily) {
      return p.copyWith(startFrom: _dateOnly(p.startFrom));
    }

    // 월급이면 monthlyStartDay 보정
    if (p.cycle == PayCycleType.monthly) {
      final msd = (p.monthlyStartDay ?? 1).clamp(1, 31);
      return p.copyWith(
        startFrom: _dateOnly(p.startFrom),
        monthlyStartDay: msd,
      );
    }

    // 그 외는 MVP 기본값으로 통일
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: now,
      monthlyStartDay: 1,
      payRule: p.payRule,
    );
  }

  _MvpPayrollKind _kindFromPolicy(PayrollPolicy p) {
    if (p.cycle == PayCycleType.daily) return _MvpPayrollKind.shortTermDaily;

    final msd = (p.monthlyStartDay ?? 1).clamp(1, 31);
    if (msd == 1) return _MvpPayrollKind.calendarMonth;
    return _MvpPayrollKind.anchorMonth;
  }

  void _applyKind(_MvpPayrollKind k) {
    setState(() {
      _kind = k;
      final now = _dateOnly(DateTime.now());

      switch (k) {
        case _MvpPayrollKind.calendarMonth:
          _policy = PayrollPolicy(
            cycle: PayCycleType.monthly,
            startFrom: now,
            monthlyStartDay: 1,
            payRule: _policy.payRule,
          );
          break;

        case _MvpPayrollKind.anchorMonth:
          // 기준 시작일은 1일이면 "캘린더월"이랑 겹치니까 기본 16일로 유도
          final cur = (_policy.monthlyStartDay ?? 16).clamp(1, 31);
          final anchorStartDay = (cur == 1) ? 16 : cur;
          _policy = PayrollPolicy(
            cycle: PayCycleType.monthly,
            startFrom: now,
            monthlyStartDay: anchorStartDay,
            payRule: _policy.payRule,
          );
          break;

        case _MvpPayrollKind.shortTermDaily:
          _policy = PayrollPolicy(
            cycle: PayCycleType.daily,
            startFrom: now,
            payRule: _policy.payRule,
          );
          break;
      }
    });
  }

  void _setPayRule(PayDateRule rule) {
    setState(() => _policy = _policy.copyWith(payRule: rule));
  }

  Future<void> _pickAnchorStartDay() async {
    final current = (_policy.monthlyStartDay ?? 16).clamp(1, 31);
    final picked = await _pickDay1to31(
      title: AppWords.policyAnchorPickTitle,
      initialDay: current,
    );
    if (picked == null) return;

    setState(() {
      // 1일은 캘린더월과 구분이 애매해져서 2일 이상으로 보정
      final safe = (picked == 1) ? 2 : picked;
      _policy = _policy.copyWith(monthlyStartDay: safe);
    });
  }

  Future<void> _pickMonthlyPayDay() async {
    final current = (_policy.payRule.monthlyDay ?? 10).clamp(1, 31);
    final picked = await _pickDay1to31(
      title: AppWords.policyPickMonthlyPayDayTitle,
      initialDay: current,
    );
    if (picked == null) return;
    _setPayRule(PayDateRule.nextMonthlyDay(picked));
  }

  Future<int?> _pickDay1to31({
    required String title,
    required int initialDay,
  }) async {
    int temp = initialDay;

    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(AppWords.close),
                    ),
                    const Spacer(),
                    Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, temp),
                      child: const Text(AppWords.select),
                    ),
                  ],
                ),
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 44,
                    physics: const FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(
                        initialItem: initialDay - 1),
                    onSelectedItemChanged: (i) => temp = i + 1,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 31,
                      builder: (_, i) => Center(
                        child: Text(
                          '${i + 1}${AppWords.dayUnit}',
                          style: const TextStyle(fontSize: 18),
                        ),
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
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _kindDesc() {
    switch (_kind) {
      case _MvpPayrollKind.calendarMonth:
        return '매달 1일~말일까지 일한 걸 한 번에 계산해요.';
      case _MvpPayrollKind.anchorMonth:
        final s = (_policy.monthlyStartDay ?? 16).clamp(1, 31);
        final end = (s == 1) ? 31 : (s - 1);
        return '매달 $s일부터 다음달 $end일까지를 한 번으로 계산해요.';
      case _MvpPayrollKind.shortTermDaily:
        return '일한 하루가 바로 계산 단위예요.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Row(
                  children: [
                    Text(
                      AppWords.payrollPolicyTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _policy),
                      child: const Text(AppWords.done),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Row(
                      children: [
                        _StepChip(label: AppWords.step1, on: _step == 0),
                        const SizedBox(width: 8),
                        _StepChip(label: AppWords.step2, on: _step == 1),
                        const SizedBox(width: 8),
                        _StepChip(label: AppWords.step3, on: _step == 2),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // STEP 0
                    if (_step == 0)
                      _Card(
                        title: AppWords.policyBundleQuestion,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _radioKind(
                              _MvpPayrollKind.calendarMonth,
                              AppWords.policyKindCalendarMonth,
                              subtitle: AppWords.policyKindCalendarMonthSub,
                            ),
                            _radioKind(
                              _MvpPayrollKind.anchorMonth,
                              AppWords.policyKindAnchorMonth,
                              subtitle: AppWords.policyKindAnchorMonthSub,
                            ),
                            _radioKind(
                              _MvpPayrollKind.shortTermDaily,
                              AppWords.policyKindDaily,
                              subtitle: AppWords.policyKindDailySub,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _kindDesc(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.65),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // STEP 1
                    if (_step == 1)
                      _Card(
                        title: '기준일 선택(이 방식일 때만)',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_kind == _MvpPayrollKind.anchorMonth) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '기준 시작일: ${(_policy.monthlyStartDay ?? 16).clamp(1, 31)}${AppWords.dayUnit}',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _pickAnchorStartDay,
                                    child: const Text(AppWords.change),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '예: 16일로 하면 1/16~2/15가 한 묶음이에요.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65),
                                ),
                              ),
                            ] else ...[
                              Text(
                                '이 방식이 아닐 때는 자동으로 정해져요.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    // STEP 2
                    if (_step == 2)
                      _Card(
                        title: AppWords.policyPayWhenTitle,
                        child: Column(
                          children: [
                            _radioPayRule(
                              PayDateRuleType.samePeriodEndDay,
                              AppWords.policyPaySameEnd,
                              onSelect: () => _setPayRule(
                                const PayDateRule.samePeriodEndDay(),
                              ),
                            ),
                            _radioPayRule(
                              PayDateRuleType.afterEndPlusDays,
                              AppWords.policyPayAfterDays,
                              onSelect: () {
                                final n =
                                    int.tryParse(_afterDaysCtrl.text.trim()) ??
                                        0;
                                _setPayRule(PayDateRule.afterEndPlusDays(
                                    n.clamp(0, 365)));
                              },
                              trailing: SizedBox(
                                width: 110,
                                child: TextField(
                                  controller: _afterDaysCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '예: 3',
                                  ),
                                  onChanged: (_) {
                                    if (_policy.payRule.type !=
                                        PayDateRuleType.afterEndPlusDays)
                                      return;
                                    final n = int.tryParse(
                                            _afterDaysCtrl.text.trim()) ??
                                        0;
                                    _setPayRule(PayDateRule.afterEndPlusDays(
                                        n.clamp(0, 365)));
                                  },
                                ),
                              ),
                            ),
                            _radioPayRule(
                              PayDateRuleType.nextMonthlyDay,
                              AppWords.policyPayMonthlyDay,
                              onSelect: () {
                                final day = (_policy.payRule.monthlyDay ?? 10)
                                    .clamp(1, 31);
                                _setPayRule(PayDateRule.nextMonthlyDay(day));
                              },
                              trailing: TextButton(
                                onPressed: _pickMonthlyPayDay,
                                child: const Text(AppWords.policyPickDate),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '예시)\n'
                              '마감이 2/15이고, 매달 25일 지급 → 2/25에 지급\n'
                              '마감이 2/15이고, 매달 10일 지급 → 3/10에 지급',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.65),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // PREVIEW
                    _Card(
                      title: AppWords.previewTitle,
                      child: Column(
                        children: _previews.map((p) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_fmtDate(p.period.start)} ~ ${_fmtDate(p.period.end)}',
                                  ),
                                ),
                                Text(
                                  '지급일: ${_fmtDate(p.payDate)}',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _step == 0
                                ? null
                                : () => setState(() => _step--),
                            child: const Text(AppWords.back),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (_step < 2) {
                                setState(() => _step++);
                              } else {
                                Navigator.pop(context, _policy);
                              }
                            },
                            child:
                                Text(_step < 2 ? AppWords.next : AppWords.done),
                          ),
                        ),
                      ],
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

  Widget _radioKind(
    _MvpPayrollKind v,
    String label, {
    String? subtitle,
  }) {
    final on = _kind == v;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<bool>(
        value: true,
        groupValue: on,
        onChanged: (_) => _applyKind(v),
      ),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => _applyKind(v),
      dense: true,
    );
  }

  Widget _radioPayRule(
    PayDateRuleType type,
    String label, {
    required VoidCallback onSelect,
    Widget? trailing,
  }) {
    final on = _policy.payRule.type == type;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<bool>(
        value: true,
        groupValue: on,
        onChanged: (_) => onSelect(),
      ),
      title: Text(label),
      trailing: trailing,
      onTap: onSelect,
      dense: true,
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.on});
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on
            ? theme.colorScheme.primary.withOpacity(0.14)
            : theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style:
            theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
