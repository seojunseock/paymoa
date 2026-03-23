import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'policies.dart' as pol;

class PolicySheetResult {
  final pol.TaxConfig tax;
  final pol.InsuranceConfig ins;
  final pol.SurchargePolicy? surcharge;
  const PolicySheetResult(
      {required this.tax, required this.ins, this.surcharge});
}

Future<PolicySheetResult?> showPolicySheet({
  required BuildContext context,
  required pol.TaxConfig initialTax,
  required pol.InsuranceConfig initialIns,
  required pol.SurchargePolicy? initialSurcharge,

  /// true(기본): 주휴수당·연장수당 토글 표시
  /// false: alba_form_screen처럼 인라인 토글이 있을 때 숨김
  bool showWeeklyToggles = true,
}) {
  return showModalBottomSheet<PolicySheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF8F7FF),
    builder: (ctx) => _PolicySheetBody(
      initialTax: initialTax,
      initialIns: initialIns,
      initialSurcharge: initialSurcharge,
      showWeeklyToggles: showWeeklyToggles,
    ),
  );
}

class _PolicySheetBody extends StatefulWidget {
  const _PolicySheetBody({
    required this.initialTax,
    required this.initialIns,
    required this.initialSurcharge,
    this.showWeeklyToggles = true,
  });
  final pol.TaxConfig initialTax;
  final pol.InsuranceConfig initialIns;
  final pol.SurchargePolicy? initialSurcharge;
  final bool showWeeklyToggles;

  @override
  State<_PolicySheetBody> createState() => _PolicySheetBodyState();
}

class _PolicySheetBodyState extends State<_PolicySheetBody> {
  late pol.TaxConfig _tax;
  late pol.InsuranceConfig _ins;
  late bool _customTaxMode;
  late final TextEditingController _customTaxCtl;

  // ── 주휴수당
  late bool _weeklyHolidayOn;

  // ── 연장수당 (일 8시간 초과)
  late bool _dailyOverOn;
  late final TextEditingController _dailyOverPctCtl;

  // ── 주 40시간 초과 연장수당
  late bool _weeklyOverOn;
  late final TextEditingController _weeklyOverPctCtl;

  // ── 휴일수당
  late bool _holOn;
  late final TextEditingController _holPctCtl;

  // ── 야간수당
  late bool _nightOn;
  late final TextEditingController _nightPctCtl;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSurcharge;
    _tax = widget.initialTax;
    _ins = widget.initialIns;
    _customTaxMode = widget.initialTax is pol.TaxConfigCustomPercent;
    _customTaxCtl = TextEditingController(
      text: _customTaxMode
          ? _trimPct((widget.initialTax as pol.TaxConfigCustomPercent).percent)
          : '',
    );

    _weeklyHolidayOn = s?.weeklyHolidayEnabled ?? false;

    // 연장수당: rule에 따라 분리
    final isDailyOver = s != null &&
        s.overtimeEnabled &&
        s.overtimeRule == pol.OvertimeRule.dailyOver8;
    final isWeeklyOver = s != null &&
        s.overtimeEnabled &&
        s.overtimeRule == pol.OvertimeRule.weeklyOver40;
    _dailyOverOn = isDailyOver;
    _weeklyOverOn = isWeeklyOver;

    _dailyOverPctCtl = TextEditingController(
        text: _trimPct(isDailyOver ? (s?.overtimePercent ?? 50) : 50));
    _weeklyOverPctCtl = TextEditingController(
        text: _trimPct(isWeeklyOver ? (s?.overtimePercent ?? 50) : 50));

    _holOn = s?.holidayEnabled ?? false;
    _holPctCtl = TextEditingController(text: _trimPct(s?.holidayPercent ?? 50));
    _nightOn = s?.nightEnabled ?? false;
    _nightPctCtl = TextEditingController(text: _trimPct(s?.nightPercent ?? 50));
  }

  @override
  void dispose() {
    _customTaxCtl.dispose();
    _dailyOverPctCtl.dispose();
    _weeklyOverPctCtl.dispose();
    _holPctCtl.dispose();
    _nightPctCtl.dispose();
    super.dispose();
  }

  pol.SurchargePolicy? _buildSurcharge() {
    final anyOn =
        _weeklyHolidayOn || _dailyOverOn || _weeklyOverOn || _holOn || _nightOn;
    if (!anyOn) return null;

    final base = widget.initialSurcharge ?? const pol.SurchargePolicy();

    // 연장수당: 일 8시간 / 주 40시간 중 하나만 선택 (마지막 켠 쪽 우선)
    // 둘 다 켜져 있으면 둘 다 처리 - 별도 필드로 저장
    final overEnabled = _dailyOverOn || _weeklyOverOn;
    // 둘 다 켤 수 없도록 UI에서 제어하지만 혹시를 위해
    final overRule = _weeklyOverOn
        ? pol.OvertimeRule.weeklyOver40
        : pol.OvertimeRule.dailyOver8;
    final overPct = _weeklyOverOn
        ? (int.tryParse(_digitsOnly(_weeklyOverPctCtl.text)) ?? 50)
        : (int.tryParse(_digitsOnly(_dailyOverPctCtl.text)) ?? 50);

    return pol.SurchargePolicy(
      weeklyHolidayEnabled: _weeklyHolidayOn,
      weeklyHolidayWeekday: base.weeklyHolidayWeekday,
      weeklyHolidayUseFixedMinutes: base.weeklyHolidayUseFixedMinutes,
      weeklyHolidayFixedMinutes: base.weeklyHolidayFixedMinutes,
      overtimeEnabled: overEnabled,
      overtimePercent: overEnabled ? overPct : 0,
      overtimeRule: overRule,
      holidayEnabled: _holOn,
      holidayPercent: int.tryParse(_digitsOnly(_holPctCtl.text)) ?? 50,
      holidayUseKoreanLawTier: base.holidayUseKoreanLawTier,
      extraHolidayYmds: base.extraHolidayYmds,
      nightEnabled: _nightOn,
      nightPercent: int.tryParse(_digitsOnly(_nightPctCtl.text)) ?? 50,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
            child: Row(
              children: [
                const Text('세금·보험·추가수당',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827))),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(
                      context,
                      PolicySheetResult(
                          tax: _tax, ins: _ins, surcharge: _buildSurcharge())),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('완료',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF0F0F5)),

          // ── 스크롤 본문
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 32 + keyboardH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ 세금 ═══
                  const _SectionTitle(text: '세금'),
                  const SizedBox(height: 8),
                  _RadioTile(
                    label: '없음',
                    desc: '세금 공제 없이 전액 받아요',
                    selected: _tax == pol.TaxConfig.none && !_customTaxMode,
                    onTap: () => setState(() {
                      _tax = pol.TaxConfig.none;
                      _customTaxMode = false;
                    }),
                  ),
                  const SizedBox(height: 6),
                  _RadioTile(
                    label: '3.3%',
                    desc: '프리랜서·아르바이트에 가장 많이 써요',
                    selected: _tax == pol.TaxConfig.biz33,
                    onTap: () => setState(() {
                      _tax = pol.TaxConfig.biz33;
                      _customTaxMode = false;
                    }),
                  ),
                  const SizedBox(height: 6),
                  _RadioTile(
                    label: '6.6%',
                    desc: '일용직 근로소득세',
                    selected: _tax == pol.TaxConfig.day66,
                    onTap: () => setState(() {
                      _tax = pol.TaxConfig.day66;
                      _customTaxMode = false;
                    }),
                  ),
                  const SizedBox(height: 6),
                  _RadioTile(
                    label: '직접 입력',
                    desc: '세율을 직접 입력해요',
                    selected: _customTaxMode,
                    onTap: () => setState(() {
                      _customTaxMode = true;
                      _tax = pol.TaxConfigCustomPercent(
                          double.tryParse(_customTaxCtl.text) ?? 0.0);
                    }),
                  ),
                  if (_customTaxMode) ...[
                    const SizedBox(height: 6),
                    _BigNumberInput(
                      controller: _customTaxCtl,
                      suffix: '%',
                      hint: '0.0',
                      onChanged: (s) => setState(() {
                        _tax = pol.TaxConfigCustomPercent(
                            double.tryParse(s) ?? 0.0);
                      }),
                      allowDecimal: true,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ═══ 보험 ═══
                  const _SectionTitle(text: '4대보험'),
                  const SizedBox(height: 8),
                  _RadioTile(
                    label: '없음',
                    desc: '보험 공제 없이 받아요',
                    selected: _ins is pol.InsuranceNone,
                    onTap: () =>
                        setState(() => _ins = const pol.InsuranceNone()),
                  ),
                  const SizedBox(height: 6),
                  _RadioTile(
                    label: '고용보험만',
                    desc: '나중에 실업급여를 받을 수 있어요',
                    selected: _ins is pol.InsuranceEmploymentOnly,
                    onTap: () => setState(
                        () => _ins = const pol.InsuranceEmploymentOnly()),
                  ),
                  const SizedBox(height: 6),
                  _RadioTile(
                    label: '4대보험 전체',
                    desc: '고용·국민연금·건강·산재 모두',
                    selected: _ins is pol.InsuranceFour,
                    onTap: () =>
                        setState(() => _ins = const pol.InsuranceFour()),
                  ),

                  const SizedBox(height: 24),

                  // ═══ 추가수당 ═══
                  const _SectionTitle(text: '추가 수당'),
                  const SizedBox(height: 8),

                  // ── 주휴수당 (showWeeklyToggles=true일 때만)
                  if (widget.showWeeklyToggles) ...[
                    _SurchargeTile(
                      label: '주휴수당',
                      desc: '주 15시간 이상 근무 시 하루치 급여 추가',
                      on: _weeklyHolidayOn,
                      controller: null,
                      onToggle: (v) => setState(() => _weeklyHolidayOn = v),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ── 일 8시간 초과 연장수당
                  _SurchargeTile(
                    label: '연장수당 (일 8시간 초과)',
                    desc: '하루 8시간 넘으면 초과분 추가 지급',
                    on: _dailyOverOn,
                    controller: _dailyOverPctCtl,
                    onToggle: (v) => setState(() {
                      _dailyOverOn = v;
                      if (v) _weeklyOverOn = false; // 둘 중 하나만
                    }),
                  ),
                  const SizedBox(height: 6),

                  // ── 주 40시간 초과 연장수당 (showWeeklyToggles=true일 때만)
                  if (widget.showWeeklyToggles) ...[
                    _SurchargeTile(
                      label: '연장수당 (주 40시간 초과)',
                      desc: '한 주 40시간 넘으면 초과분 추가 지급',
                      on: _weeklyOverOn,
                      controller: _weeklyOverPctCtl,
                      onToggle: (v) => setState(() {
                        _weeklyOverOn = v;
                        if (v) _dailyOverOn = false; // 둘 중 하나만
                      }),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ── 휴일수당
                  _SurchargeTile(
                    label: '휴일 근무 수당',
                    desc: '공휴일이나 쉬는 날 근무',
                    on: _holOn,
                    controller: _holPctCtl,
                    onToggle: (v) => setState(() => _holOn = v),
                  ),
                  const SizedBox(height: 6),

                  // ── 야간수당
                  _SurchargeTile(
                    label: '야간 수당',
                    desc: '밤 10시 ~ 새벽 6시',
                    on: _nightOn,
                    controller: _nightPctCtl,
                    onToggle: (v) => setState(() => _nightOn = v),
                  ),
                ],
              ),
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
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151)));
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _purple : const Color(0xFFD1D5DB),
                  width: selected ? 5.0 : 1.8,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected ? _purple : const Color(0xFF111827))),
                  const SizedBox(height: 1),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 큰 숫자 입력칸
class _BigNumberInput extends StatelessWidget {
  const _BigNumberInput({
    required this.controller,
    required this.suffix,
    required this.hint,
    required this.onChanged,
    this.allowDecimal = false,
  });
  final TextEditingController controller;
  final String suffix;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF7C3AED).withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: allowDecimal),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]')),
              ],
              textAlign: TextAlign.right,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF7C3AED),
                letterSpacing: -0.5,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE5E7EB)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 6),
          Text(suffix,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151))),
        ],
      ),
    );
  }
}

// 수당 토글 타일 (controller == null이면 퍼센트 입력 없음)
class _SurchargeTile extends StatelessWidget {
  const _SurchargeTile({
    required this.label,
    required this.desc,
    required this.on,
    required this.controller,
    required this.onToggle,
  });
  final String label;
  final String desc;
  final bool on;
  final TextEditingController? controller;
  final ValueChanged<bool> onToggle;

  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      decoration: BoxDecoration(
        color: on ? _purple.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: on ? _purple.withOpacity(0.40) : const Color(0xFFE5E7EB),
          width: on ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // 토글 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: on ? _purple : const Color(0xFF111827))),
                      Text(desc,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                Switch(
                  value: on,
                  onChanged: onToggle,
                  activeColor: _purple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          // 켜졌을 때 % 입력칸 (controller가 있을 때만)
          if (on && controller != null) ...[
            Container(height: 1, color: _purple.withOpacity(0.10)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  const Text('기본 시급의',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _purple),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: _purple.withOpacity(0.07),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('% 추가 지급',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

String _trimPct(num v) {
  if (v is int) return v.toString();
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
