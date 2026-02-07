import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'policies.dart' as pol;

/// 정책 시트 결과
class PolicySheetResult {
  final pol.TaxConfig tax;
  final pol.InsuranceConfig ins;
  final pol.SurchargePolicy? surcharge;
  const PolicySheetResult(
      {required this.tax, required this.ins, this.surcharge});
}

/// ✅ 컨트롤러를 "build마다 새로 만들지 않고" 상태로 유지하는 정책 시트
Future<PolicySheetResult?> showPolicySheet({
  required BuildContext context,
  required pol.TaxConfig initialTax,
  required pol.InsuranceConfig initialIns,
  required pol.SurchargePolicy? initialSurcharge,
}) {
  return showModalBottomSheet<PolicySheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _PolicySheetBody(
        initialTax: initialTax,
        initialIns: initialIns,
        initialSurcharge: initialSurcharge,
      );
    },
  );
}

class _PolicySheetBody extends StatefulWidget {
  const _PolicySheetBody({
    required this.initialTax,
    required this.initialIns,
    required this.initialSurcharge,
  });

  final pol.TaxConfig initialTax;
  final pol.InsuranceConfig initialIns;
  final pol.SurchargePolicy? initialSurcharge;

  @override
  State<_PolicySheetBody> createState() => _PolicySheetBodyState();
}

class _PolicySheetBodyState extends State<_PolicySheetBody> {
  late pol.TaxConfig _tax;
  late pol.InsuranceConfig _ins;

  // 세금: 커스텀 모드 + 입력 컨트롤러(유지)
  late bool _customTaxMode;
  late final TextEditingController _customTaxCtl;

  // 가산정책 토글
  late bool _weekly;

  late bool _overOn;
  late bool _holOn;
  late bool _nightOn;

  // 가산율 컨트롤러(유지)
  late final TextEditingController _overPctCtl;
  late final TextEditingController _holPctCtl;
  late final TextEditingController _nightPctCtl;

  @override
  void initState() {
    super.initState();

    _tax = widget.initialTax;
    _ins = widget.initialIns;

    _weekly = widget.initialSurcharge?.weeklyHolidayEnabled ?? false;

    _overOn = widget.initialSurcharge?.overtimeEnabled ?? false;
    _holOn = widget.initialSurcharge?.holidayEnabled ?? false;
    _nightOn = widget.initialSurcharge?.nightEnabled ?? false;

    _customTaxMode = widget.initialTax is pol.TaxConfigCustomPercent;
    final customTax = (widget.initialTax is pol.TaxConfigCustomPercent)
        ? _trimPct((widget.initialTax as pol.TaxConfigCustomPercent).percent)
        : '';
    _customTaxCtl = TextEditingController(text: customTax);

    final overPct = _trimPct(widget.initialSurcharge?.overtimePercent ?? 50);
    final holPct = _trimPct(widget.initialSurcharge?.holidayPercent ?? 50);
    final nightPct = _trimPct(widget.initialSurcharge?.nightPercent ?? 50);

    _overPctCtl = TextEditingController(text: overPct);
    _holPctCtl = TextEditingController(text: holPct);
    _nightPctCtl = TextEditingController(text: nightPct);
  }

  @override
  void dispose() {
    _customTaxCtl.dispose();
    _overPctCtl.dispose();
    _holPctCtl.dispose();
    _nightPctCtl.dispose();
    super.dispose();
  }

  pol.SurchargePolicy? _buildSurcharge() {
    if (!(_weekly || _overOn || _holOn || _nightOn)) return null;
    return pol.SurchargePolicy(
      weeklyHolidayEnabled: _weekly,
      overtimeEnabled: _overOn,
      overtimePercent: int.tryParse(_digitsOnly(_overPctCtl.text)) ?? 0,
      holidayEnabled: _holOn,
      holidayPercent: int.tryParse(_digitsOnly(_holPctCtl.text)) ?? 0,
      nightEnabled: _nightOn,
      nightPercent: int.tryParse(_digitsOnly(_nightPctCtl.text)) ?? 0,
    );
  }

  void _applyCustomTaxText(String text) {
    final f = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (f != _customTaxCtl.text) {
      // 입력 중에도 컨트롤러 유지(커서 튐 방지)
      final oldSel = _customTaxCtl.selection;
      _customTaxCtl.value = TextEditingValue(
        text: f,
        selection: oldSel.copyWith(
          baseOffset: f.length.clamp(0, f.length),
          extentOffset: f.length.clamp(0, f.length),
        ),
      );
    }
    final pct = double.tryParse(f) ?? 0.0;
    _tax = pol.TaxConfigCustomPercent(pct);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소')),
                const Spacer(),
                Text('세금/보험/가산정책 설정', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      PolicySheetResult(
                          tax: _tax, ins: _ins, surcharge: _buildSurcharge()),
                    );
                  },
                  child: const Text('완료'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _Section(
                      title: '세금',
                      child: Column(
                        children: [
                          RadioListTile<pol.TaxConfig>(
                            title: const Text('없음'),
                            value: pol.TaxConfig.none,
                            groupValue: _tax,
                            onChanged: (v) => setState(() {
                              _tax = v ?? _tax;
                              _customTaxMode = false;
                            }),
                          ),
                          RadioListTile<pol.TaxConfig>(
                            title: const Text('사업소득 3.3%'),
                            value: pol.TaxConfig.biz33,
                            groupValue: _tax,
                            onChanged: (v) => setState(() {
                              _tax = v ?? _tax;
                              _customTaxMode = false;
                            }),
                          ),
                          RadioListTile<pol.TaxConfig>(
                            title: const Text('일용직 6.6%'),
                            value: pol.TaxConfig.day66,
                            groupValue: _tax,
                            onChanged: (v) => setState(() {
                              _tax = v ?? _tax;
                              _customTaxMode = false;
                            }),
                          ),
                          ListTile(
                            title: const Text('직접 입력(%)'),
                            trailing: Switch(
                              value: _customTaxMode,
                              onChanged: (on) => setState(() {
                                _customTaxMode = on;
                                _tax = on
                                    ? pol.TaxConfigCustomPercent(
                                        double.tryParse(_customTaxCtl.text) ??
                                            0.0)
                                    : pol.TaxConfig.none;
                              }),
                            ),
                          ),
                          if (_customTaxMode)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: TextField(
                                controller: _customTaxCtl, // ✅ 유지되는 컨트롤러
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]')),
                                ],
                                decoration: const InputDecoration(
                                    labelText: '세율(%) 예: 5.0'),
                                onChanged: (s) =>
                                    setState(() => _applyCustomTaxText(s)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Section(
                      title: '보험',
                      child: Column(
                        children: [
                          RadioListTile<pol.InsuranceConfig>(
                            title: const Text('없음'),
                            value: const pol.InsuranceNone(),
                            groupValue: _ins,
                            onChanged: (v) => setState(() => _ins = v ?? _ins),
                          ),
                          RadioListTile<pol.InsuranceConfig>(
                            title: const Text('고용보험만'),
                            value: const pol.InsuranceEmploymentOnly(),
                            groupValue: _ins,
                            onChanged: (v) => setState(() => _ins = v ?? _ins),
                          ),
                          RadioListTile<pol.InsuranceConfig>(
                            title: const Text('4대보험'),
                            value: const pol.InsuranceFour(),
                            groupValue: _ins,
                            onChanged: (v) => setState(() => _ins = v ?? _ins),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Section(
                      title: '가산정책',
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('주휴수당 사용'),
                            value: _weekly,
                            onChanged: (on) => setState(() => _weekly = on),
                          ),
                          const Divider(),
                          _SRow(
                            title: '연장근로 수당',
                            on: _overOn,
                            controller: _overPctCtl, // ✅ 유지되는 컨트롤러
                            onToggle: (on) => setState(() => _overOn = on),
                          ),
                          const SizedBox(height: 8),
                          _SRow(
                            title: '휴일 근로 수당',
                            on: _holOn,
                            controller: _holPctCtl, // ✅ 유지되는 컨트롤러
                            onToggle: (on) => setState(() => _holOn = on),
                          ),
                          const SizedBox(height: 8),
                          _SRow(
                            title: '야간 근로 수당 (22:00~06:00)',
                            on: _nightOn,
                            controller: _nightPctCtl, // ✅ 유지되는 컨트롤러
                            onToggle: (on) => setState(() => _nightOn = on),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SRow extends StatelessWidget {
  const _SRow({
    required this.title,
    required this.on,
    required this.controller,
    required this.onToggle,
  });

  final String title;
  final bool on;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Switch(value: on, onChanged: onToggle),
          ],
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: TextField(
              controller: controller, // ✅ 유지
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '가산율(%) 예: 50'),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
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
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          child,
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
