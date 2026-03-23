// lib/screens/payroll_policy_sheet.dart
import 'package:flutter/cupertino.dart';
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
    backgroundColor: const Color(0xFFF8F7FF),
    builder: (ctx) {
      return _PayrollPolicySheet(role: role, initialPolicy: initial);
    },
  );
}

enum _MvpPayrollKind { calendarMonth, anchorMonth, shortTermDaily }

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
  late PayrollPolicy _policy;
  late _MvpPayrollKind _kind;
  final _afterDaysCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _policy = _normalizeToMvp(widget.initialPolicy);
    _kind = _kindFromPolicy(_policy);
    if (_policy.payRule.type == PayDateRuleType.afterEndPlusDays) {
      _afterDaysCtrl.text = '${_policy.payRule.plusDays ?? 0}';
    }
  }

  @override
  void dispose() {
    _afterDaysCtrl.dispose();
    super.dispose();
  }

  /* ─── 로직 ─── */
  PeriodPayPreview get _preview =>
      _engine.previewNext(policy: _policy, count: 1).first;

  PayrollPolicy _normalizeToMvp(PayrollPolicy p) {
    final now = _dateOnly(DateTime.now());
    if (p.cycle == PayCycleType.daily)
      return p.copyWith(startFrom: _dateOnly(p.startFrom));
    if (p.cycle == PayCycleType.monthly) {
      return p.copyWith(
          startFrom: _dateOnly(p.startFrom),
          monthlyStartDay: (p.monthlyStartDay ?? 1).clamp(1, 31));
    }
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: now,
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(25),
    );
  }

  _MvpPayrollKind _kindFromPolicy(PayrollPolicy p) {
    if (p.cycle == PayCycleType.daily) return _MvpPayrollKind.shortTermDaily;
    final s = p.monthlyStartDay ?? 1;
    return (s == 1)
        ? _MvpPayrollKind.calendarMonth
        : _MvpPayrollKind.anchorMonth;
  }

  void _applyKind(_MvpPayrollKind k) {
    final now = _dateOnly(DateTime.now());
    setState(() {
      _kind = k;
      switch (k) {
        case _MvpPayrollKind.calendarMonth:
          _policy = PayrollPolicy(
            cycle: PayCycleType.monthly,
            startFrom: now,
            monthlyStartDay: 1,
            payRule: _policy.payRule,
          );
        case _MvpPayrollKind.anchorMonth:
          final s = (_policy.monthlyStartDay ?? 16) == 1
              ? 16
              : (_policy.monthlyStartDay ?? 16);
          _policy = PayrollPolicy(
            cycle: PayCycleType.monthly,
            startFrom: now,
            monthlyStartDay: s,
            payRule: _policy.payRule,
          );
        case _MvpPayrollKind.shortTermDaily:
          _policy = PayrollPolicy(
            cycle: PayCycleType.daily,
            startFrom: now,
            payRule: _policy.payRule,
          );
      }
    });
  }

  void _setPayRule(PayDateRule r) =>
      setState(() => _policy = _policy.copyWith(payRule: r));

  Future<void> _pickAnchorStartDay() async {
    final cur = (_policy.monthlyStartDay ?? 16).clamp(1, 31);
    int tmp = cur;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 280,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                const Text('시작일 선택',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _policy = _policy.copyWith(
                        monthlyStartDay: tmp,
                        startFrom: _dateOnly(DateTime.now()),
                      );
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('확인'),
                ),
              ]),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 44,
                scrollController:
                    FixedExtentScrollController(initialItem: cur - 1),
                onSelectedItemChanged: (i) => tmp = i + 1,
                children: List.generate(
                    31, (i) => Center(child: Text('매달 ${i + 1}일'))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAfterDays(BuildContext context) async {
    final cur = (_policy.payRule.plusDays ?? 0).clamp(0, 60);
    int tmp = cur;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 280,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                const Text('며칠 뒤에 받을까요?',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _setPayRule(PayDateRule.afterEndPlusDays(tmp));
                    Navigator.pop(ctx);
                  },
                  child: const Text('확인',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7C3AED))),
                ),
              ]),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 44,
                scrollController: FixedExtentScrollController(initialItem: cur),
                onSelectedItemChanged: (i) => tmp = i,
                children: List.generate(
                    61,
                    (i) => Center(
                          child: Text(
                            i == 0 ? '마감일 당일' : '$i일 뒤',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMonthlyPayDay() async {
    final cur = (_policy.payRule.monthlyDay ?? 25).clamp(1, 31);
    int tmp = cur;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 280,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                const Text('급여일 선택',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _setPayRule(PayDateRule.nextMonthlyDay(tmp));
                    Navigator.pop(ctx);
                  },
                  child: const Text('확인'),
                ),
              ]),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 44,
                scrollController:
                    FixedExtentScrollController(initialItem: cur - 1),
                onSelectedItemChanged: (i) => tmp = i + 1,
                children: List.generate(
                    31, (i) => Center(child: Text('매달 ${i + 1}일'))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  // anchor 기준일 → 마감일 계산
  String _anchorDesc(int startDay) {
    final endDay = startDay == 1 ? '말일' : '${startDay - 1}일';
    return '매달 ${startDay}일 ~ 다음달 $endDay';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /* ─── UI ─── */
  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final anchorDay = (_policy.monthlyStartDay ?? 16).clamp(1, 31);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
              // ── 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
                child: Row(
                  children: [
                    const Text('급여 방식 설정',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _policy),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('완료',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFF0F0F5)),

              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  children: [
                    // ── 섹션 1: 계산 기간
                    const _SectionTitle(text: '일한 기간을 어떻게 묶을까요?'),
                    const SizedBox(height: 10),

                    _RadioTile(
                      label: '매달 1일 ~ 말일',
                      desc: '가장 많이 쓰는 방식이에요',
                      selected: _kind == _MvpPayrollKind.calendarMonth,
                      onTap: () => _applyKind(_MvpPayrollKind.calendarMonth),
                    ),
                    const SizedBox(height: 6),
                    _RadioTile(
                      label: _kind == _MvpPayrollKind.anchorMonth
                          ? _anchorDesc(anchorDay)
                          : '매달 16일 ~ 다음달 15일',
                      desc: _kind == _MvpPayrollKind.anchorMonth
                          ? '위 버튼으로 날짜를 바꿀 수 있어요'
                          : '시작일을 직접 정할 수 있어요',
                      selected: _kind == _MvpPayrollKind.anchorMonth,
                      onTap: () => _applyKind(_MvpPayrollKind.anchorMonth),
                      trailing: _kind == _MvpPayrollKind.anchorMonth
                          ? GestureDetector(
                              onTap: _pickAnchorStartDay,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${anchorDay}일 시작',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    _RadioTile(
                      label: '일급',
                      desc: '하루씩 따로 계산해요',
                      selected: _kind == _MvpPayrollKind.shortTermDaily,
                      onTap: () => _applyKind(_MvpPayrollKind.shortTermDaily),
                    ),

                    const SizedBox(height: 24),

                    // ── 섹션 2: 급여일
                    const _SectionTitle(text: '급여는 언제 주나요?'),
                    const SizedBox(height: 10),

                    _RadioTile(
                      label: '정산 마지막 날에 바로',
                      desc: '계산 기간이 끝나는 날에 받아요',
                      selected: _policy.payRule.type ==
                          PayDateRuleType.samePeriodEndDay,
                      onTap: () =>
                          _setPayRule(const PayDateRule.samePeriodEndDay()),
                    ),
                    const SizedBox(height: 6),

                    // 마감 후 N일
                    _RadioTile(
                      label: '정산 끝나고 며칠 뒤',
                      desc: '마감일로부터 며칠 뒤에 받아요',
                      selected: _policy.payRule.type ==
                          PayDateRuleType.afterEndPlusDays,
                      onTap: () {
                        final n = int.tryParse(_afterDaysCtrl.text.trim()) ?? 0;
                        _setPayRule(
                            PayDateRule.afterEndPlusDays(n.clamp(0, 365)));
                      },
                    ),
                    // 마감 후 N일 선택 시 아이폰 스크롤 피커
                    if (_policy.payRule.type ==
                        PayDateRuleType.afterEndPlusDays) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _pickAfterDays(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE9D5FF)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('마감 후 ',
                                  style: TextStyle(
                                      fontSize: 15, color: Color(0xFF6B7280))),
                              Text(
                                '${_policy.payRule.plusDays ?? 0}',
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF7C3AED)),
                              ),
                              const Text(' 일 뒤에 받아요',
                                  style: TextStyle(
                                      fontSize: 15, color: Color(0xFF6B7280))),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),

                    // 매달 N일
                    _RadioTile(
                      label: '매달 정해진 날짜에',
                      desc: '예: 매달 25일에 받아요',
                      selected: _policy.payRule.type ==
                          PayDateRuleType.nextMonthlyDay,
                      onTap: () {
                        final day =
                            (_policy.payRule.monthlyDay ?? 25).clamp(1, 31);
                        _setPayRule(PayDateRule.nextMonthlyDay(day));
                      },
                      trailing:
                          _policy.payRule.type == PayDateRuleType.nextMonthlyDay
                              ? GestureDetector(
                                  onTap: _pickMonthlyPayDay,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_policy.payRule.monthlyDay ?? 25}일',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white),
                                    ),
                                  ),
                                )
                              : null,
                    ),

                    const SizedBox(height: 24),

                    // ── 미리보기 (1개)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF7C3AED).withOpacity(0.15)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 15, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_fmtDate(preview.period.start)} ~ ${_fmtDate(preview.period.end)}',
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7280)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_fmtDate(preview.payDate)} 지급',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}

/* ────────────── 공통 컴포넌트 ────────────── */

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF374151),
      ),
    );
  }
}

// 라디오 행 (이모지/아이콘 없음, 깔끔)
class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.label,
    this.desc,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final String label;
  final String? desc;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _purple.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected ? _purple.withOpacity(0.45) : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // 커스텀 라디오
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _purple : const Color(0xFFD1D5DB),
                  width: selected ? 6.0 : 2.0,
                ),
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? _purple : const Color(0xFF111827),
                      )),
                  if (desc != null) ...[
                    const SizedBox(height: 2),
                    Text(desc!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? _purple.withOpacity(0.65)
                              : const Color(0xFF9CA3AF),
                        )),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

// 확장 입력칸 (마감 후 N일 등)
class _ExpandedInput extends StatelessWidget {
  const _ExpandedInput({
    required this.prefix,
    required this.suffix,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
  });
  final String prefix;
  final String suffix;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Text(prefix,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF7C3AED),
                letterSpacing: -0.5,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 10),
          Text(suffix,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}
