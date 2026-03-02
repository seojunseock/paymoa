// lib/screens/owner/owner_store_form_screen.dart
import 'package:flutter/material.dart';
import '../../common/paymoa_design.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/store.dart';
import '../../policies/policies.dart' as pol;
import '../../policies/policy_sheet.dart';
import '../../data/firebase_service.dart';
import '../../common/ui/money_text_controller.dart';
import '../../payroll/payroll.dart';
import '../../payroll/payroll_policy_mapper.dart' as ppm;
import '../payroll_policy_sheet.dart';
import 'owner_store_code_screen.dart';

/* ── 디자인 상수 (alba_form_screen 동일) ── */
const _bg = Color(0xFFF8F7FF);
const _textPrimary = Pm.textPrimary;
const _textSecondary = Pm.textSecondary;
const _textTertiary = Pm.textTertiary;
const _primaryPurple = Pm.primary;

/* ── _FormCard (alba_form_screen._FormCard 동일) ── */
class _FormCard extends StatelessWidget {
  const _FormCard({required this.child, this.label, this.trailing});
  final Widget child;
  final String? label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Pm.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pm.border, width: 1),
        boxShadow: Pm.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                Text(label!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textTertiary,
                        letterSpacing: 0.5)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ] else if (trailing != null) ...[
            Align(alignment: Alignment.centerRight, child: trailing!),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

/* ── 접이식 카드 ── */
class _OwnerSettingRow extends StatelessWidget {
  const _OwnerSettingRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280))),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
        ]),
      ),
    );
  }
}

/* ══════════════════════════════════════════════
   매장 폼 화면
   ══════════════════════════════════════════════ */

class OwnerStoreFormScreen extends StatefulWidget {
  const OwnerStoreFormScreen({super.key, this.existing});
  final Store? existing;

  @override
  State<OwnerStoreFormScreen> createState() => _OwnerStoreFormScreenState();
}

class _OwnerStoreFormScreenState extends State<OwnerStoreFormScreen> {
  final _storeName = TextEditingController();
  late final MoneyTextController _wage;

  // ── 색상
  Color _color = Pm.primary;
  String _colorHex = '#7C3AED';

  static const _paletteHex = [
    '#7C3AED',
    '#3B82F6',
    '#10B981',
    '#F59E0B',
    '#EF4444',
    '#EC4899',
    '#8B5CF6',
    '#14B8A6',
    '#F97316',
    '#6366F1',
    '#84CC16',
    '#06B6D4',
  ];
  static const _paletteColors = [
    Color(0xFF7C3AED),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFF06B6D4),
  ];

  // ── 정책
  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy _surcharge = const pol.SurchargePolicy();

  late PayrollPolicy _payrollPolicy;
  bool _saving = false;
  bool _showPalette = false;
  bool _formattingWage = false;

  final _repo = FirebaseService();
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _wage = MoneyTextController();

    // 실시간 콤마 포맷팅
    _wage.addListener(() {
      if (_formattingWage) return;
      final txt = _wage.text;
      final formatted = _formatMoneyText(txt);
      if (formatted != txt) {
        _formattingWage = true;
        _wage.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
        _formattingWage = false;
      }
    });

    final now = DateTime.now();
    _payrollPolicy = PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(10),
    );

    final s = widget.existing;
    if (s != null) {
      _storeName.text = s.name;
      _wage.setValueInt(s.defaultHourlyWage ?? 0);

      // 색상
      final hexRaw = s.colorHex ?? '#7C3AED';
      _colorHex = hexRaw;
      _color = _parseColorHex(hexRaw) ?? Pm.primary;

      _tax = s.taxConfig;
      _ins = s.insuranceConfig;
      _surcharge = s.surchargePolicy;
      _payrollPolicy = s.payrollPolicy;

      final policy =
          (s.policy ?? const <String, dynamic>{}).cast<String, dynamic>();
    }
  }

  bool _anySurcharge(pol.SurchargePolicy s) =>
      s.weeklyHolidayEnabled ||
      s.overtimeEnabled ||
      s.holidayEnabled ||
      s.nightEnabled;

  @override
  void dispose() {
    _storeName.dispose();
    _wage.dispose();
    super.dispose();
  }

  // ── 정책 시트
  Future<void> _openPolicy() async {
    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
    );
    if (r != null) {
      setState(() {
        _tax = r.tax;
        _ins = r.ins;
        _surcharge = r.surcharge ?? const pol.SurchargePolicy();
      });
    }
  }

  Future<void> _openPayrollPolicy() async {
    final res = await showPayrollPolicySheet(
      context: context,
      initial: _payrollPolicy,
      role: PayrollViewerRole.owner,
    );
    if (res != null) {
      setState(() => _payrollPolicy = _normalizePolicies(res));
    }
  }

  PayrollPolicy _normalizePolicies(PayrollPolicy p) {
    if (p.cycle == PayCycleType.monthly) {
      return p.copyWith(
        startFrom:
            DateTime(p.startFrom.year, p.startFrom.month, p.startFrom.day),
        monthlyStartDay: (p.monthlyStartDay ?? 1).clamp(1, 31),
      );
    }
    final now = DateTime.now();
    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: p.payRule,
    );
  }

  // ── submit
  Future<void> _submit() async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = _storeName.text.trim();
    if (name.isEmpty) {
      _snack('매장 이름을 적어주세요.');
      return;
    }
    final wage = _wage.valueInt;
    if (wage <= 0) {
      _snack('시급을 입력해 주세요.');
      return;
    }

    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;
    final ok = await _confirmSummary(name: name, wage: wage, preview: preview);
    if (!ok) return;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.updateStore(
          uid: user.uid,
          storeId: widget.existing!.id,
          name: name,
          colorHex: _colorHex,
          defaultHourlyWage: wage,
          payDay: _legacyPayDay(_payrollPolicy),
          policy: _policyToMap(),
        );
        if (!mounted) return;
        _snack('수정 완료!');
        Navigator.of(context).pop(true);
        return;
      }

      final store = await _repo.createStore(
        uid: user.uid,
        name: name,
        colorHex: _colorHex,
        defaultHourlyWage: wage,
        payDay: _legacyPayDay(_payrollPolicy),
        policy: _policyToMap(),
      );
      if (!mounted) return;
      final code = store.storeCode;
      if (code == null || code.isEmpty) {
        _snack('초대코드 생성 실패.');
        return;
      }

      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            OwnerStoreCodeScreen(storeName: store.name, storeCode: code),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── helpers
  Map<String, dynamic> _policyToMap() => {
        'tax': {
          'enabled': _tax != pol.TaxConfig.none,
          'value': _taxToPolicyValue(_tax)
        },
        'insurance': {
          'enabled': _ins is! pol.InsuranceNone,
          'value': _insToPolicyValue(_ins)
        },
        'surcharge': {
          'enabled': _anySurcharge(_surcharge),
          'weeklyHolidayEnabled': _surcharge.weeklyHolidayEnabled,
          'overtimeEnabled': _surcharge.overtimeEnabled,
          'overtimePercent': _surcharge.overtimePercent,
          'overtimeRule':
              _surcharge.overtimeRule == pol.OvertimeRule.weeklyOver40
                  ? 'weeklyOver40'
                  : 'dailyOver8',
          'holidayEnabled': _surcharge.holidayEnabled,
          'holidayPercent': _surcharge.holidayPercent,
          'nightEnabled': _surcharge.nightEnabled,
          'nightPercent': _surcharge.nightPercent,
        },
        'payrollPolicy': ppm.payrollPolicyToMap(_payrollPolicy),
      };

  dynamic _taxToPolicyValue(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return 'biz33';
    if (t == pol.TaxConfig.day66) return 'day66';
    if (t is pol.TaxConfigCustomPercent)
      return {'kind': 'customPercent', 'percent': t.percent};
    return 'none';
  }

  dynamic _insToPolicyValue(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return 'employmentOnly';
    if (i is pol.InsuranceFour) return 'four';
    return 'none';
  }

  int _legacyPayDay(PayrollPolicy p) => p.cycle == PayCycleType.monthly
      ? (p.monthlyStartDay ?? 1).clamp(1, 31)
      : 1;

  String _fmtYmd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _payrollSummary(PayrollPolicy p) {
    final type = p.cycle == PayCycleType.daily
        ? '일급'
        : p.cycle == PayCycleType.monthly
            ? ((p.monthlyStartDay ?? 1) == 1
                ? '한 달(1일~말일)'
                : '매달 ${p.monthlyStartDay}일 시작')
            : '급여 방식';
    final payStr = () {
      switch (p.payRule.type) {
        case PayDateRuleType.nextMonthlyDay:
          return '매달 ${p.payRule.monthlyDay ?? 10}일 지급';
        case PayDateRuleType.samePeriodEndDay:
          return '마감일 당일';
        case PayDateRuleType.afterEndPlusDays:
          return '마감 후 ${p.payRule.plusDays ?? 0}일 뒤';
        case PayDateRuleType.fixedDate:
          return '지정일 지급';
      }
    }();
    return '$type · $payStr';
  }

  Future<bool> _confirmSummary({
    required String name,
    required int wage,
    required PeriodPayPreview preview,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isEdit ? '이대로 수정할까요?' : '이대로 만들까요?'),
        content: Text(
          '매장: $name\n시급: ${_commaFmt(wage)}원\n\n'
          '급여 방식: ${_payrollSummary(_payrollPolicy)}\n'
          '이번 기간: ${_fmtYmd(preview.period.start)} ~ ${_fmtYmd(preview.period.end)}\n'
          '지급일: ${_fmtYmd(preview.payDate)}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isEdit ? '수정' : '만들기',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  String _taxLabel(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return '사업소득세 3.3%';
    if (t == pol.TaxConfig.day66) return '일용직 6.6%';
    if (t is pol.TaxConfigCustomPercent) return '커스텀 ${t.percent}%';
    return '미설정';
  }

  String _insLabel(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return '고용보험';
    if (i is pol.InsuranceFour) return '4대보험';
    return '미설정';
  }

  String _surchargeLabel(pol.SurchargePolicy s) {
    final parts = <String>[];
    if (s.weeklyHolidayEnabled) parts.add('주휴수당');
    if (s.overtimeEnabled) parts.add('연장');
    if (s.nightEnabled) parts.add('야간');
    if (s.holidayEnabled) parts.add('휴일');
    return parts.isEmpty ? '미설정' : parts.join(' · ');
  }

  // ── build
  @override
  Widget build(BuildContext context) {
    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEdit ? '매장 수정' : '매장 만들기',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 18, color: _textPrimary),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text(
              _saving ? '저장 중…' : '저장',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _saving ? _textTertiary : _color,
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        // 팔레트 외부 탭 → 닫기
        onTap: _showPalette ? () => setState(() => _showPalette = false) : null,
        behavior: HitTestBehavior.translucent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          children: [
            // ── ① 색상 + 매장명
            _FormCard(
              child: Row(
                children: [
                  // 색상 도트
                  GestureDetector(
                    onTap: () => setState(() => _showPalette = !_showPalette),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _color.withOpacity(0.45),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.palette_outlined,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _storeName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary),
                      decoration: InputDecoration(
                        hintText: '매장 이름',
                        hintStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFD1D5DB)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _color, width: 2),
                        ),
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 팔레트 (이름 카드 바로 아래)
            if (_showPalette) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(_paletteHex.length, (i) {
                    final hex = _paletteHex[i];
                    final c = _paletteColors[i];
                    final selected = hex == _colorHex;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _colorHex = hex;
                        _color = c;
                        _showPalette = false;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                      color: c.withOpacity(0.5), blurRadius: 10)
                                ]
                              : [],
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── ② 시급
            _FormCard(
              label: '시급',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wage,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        MoneyTextController.digitsOnlyFormatter
                      ],
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE5E7EB)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('원',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151))),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── ③ 공제 · 수당
            _FormCard(
              label: '세금 · 보험 · 가산',
              child: Column(
                children: [
                  _OwnerSettingRow(
                    icon: Icons.receipt_long_outlined,
                    label: '세금',
                    value: _taxLabel(_tax),
                    onTap: _openPolicy,
                  ),
                  const SizedBox(height: 2),
                  _OwnerSettingRow(
                    icon: Icons.health_and_safety_outlined,
                    label: '보험',
                    value: _insLabel(_ins),
                    onTap: _openPolicy,
                  ),
                  const SizedBox(height: 2),
                  _OwnerSettingRow(
                    icon: Icons.nightlight_outlined,
                    label: '야간 · 연장 · 휴일',
                    value: _surchargeLabel(_surcharge),
                    onTap: _openPolicy,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── ④ 급여 방식
            _FormCard(
              label: '급여 방식',
              trailing: TextButton(
                onPressed: _openPayrollPolicy,
                child: Text('설정',
                    style: TextStyle(
                        color: _color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _payrollSummary(_payrollPolicy),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '이번 기간: ${_fmtYmd(preview.period.start)} ~ ${_fmtYmd(preview.period.end)}  '
                    '지급: ${_fmtYmd(preview.payDate)}',
                    style: const TextStyle(fontSize: 14, color: _textTertiary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── ⑤ 저장 버튼
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _saving ? '저장하는 중…' : (_isEdit ? '수정 완료' : '매장 만들고 초대코드 받기'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 헬퍼
Color? _parseColorHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
  } catch (_) {
    return null;
  }
}

String _commaFmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    b.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && left % 3 == 0) b.write(',');
  }
  return b.toString();
}

String _formatMoneyText(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final noLeading = digits.replaceFirst(RegExp(r'^0+'), '');
  if (noLeading.isEmpty) return '';
  final v = int.tryParse(noLeading) ?? 0;
  return _commaFmt(v);
}
