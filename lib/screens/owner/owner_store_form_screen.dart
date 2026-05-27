// lib/screens/owner/owner_store_form_screen.dart
import 'package:flutter/material.dart';
import '../../common/paymoa_design.dart';
import '../../common/common_pickers.dart' as cp;
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
import '../../common/help_dialog.dart';

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
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
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
  const _OwnerSettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.helpTitle,
    this.helpBody,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? helpTitle;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            if (helpTitle != null) ...[
              const SizedBox(width: 6),
              helpIcon(context, title: helpTitle!, body: helpBody!),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
          ],
        ),
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

  final _storeNameFocus = FocusNode();
  final _wageFocus = FocusNode();

  // ── 색상
  Color _color = Pm.primary;
  String _colorHex = '#7C3AED';

  // ── 정책
  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy _surcharge = const pol.SurchargePolicy();

  // ── 변경 감지용 초기값
  int? _initialWage;
  pol.TaxConfig? _initialTax;
  pol.InsuranceConfig? _initialIns;
  pol.SurchargePolicy? _initialSurcharge;

  late PayrollPolicy _payrollPolicy;
  bool _saving = false;
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

      // 변경 감지용 초기값 저장
      _initialWage = s.defaultHourlyWage;
      _initialTax = s.taxConfig;
      _initialIns = s.insuranceConfig;
      _initialSurcharge = s.surchargePolicy;

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
    _storeNameFocus.dispose();
    _wageFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ── 정책 시트
  Future<void> _openPolicy() async {
    _dismissKeyboard();

    final r = await showPolicySheet(
      context: context,
      initialTax: _tax,
      initialIns: _ins,
      initialSurcharge: _surcharge,
      showWeeklyToggles: false,
    );
    if (!mounted) return;

    if (r != null) {
      setState(() {
        _tax = r.tax;
        _ins = r.ins;
        _surcharge = r.surcharge ?? const pol.SurchargePolicy();
      });
    }
  }

  Future<void> _openPayrollPolicy() async {
    _dismissKeyboard();

    final res = await showPayrollPolicySheet(
      context: context,
      initial: _payrollPolicy,
      role: PayrollViewerRole.owner,
    );
    if (!mounted) return;

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

    _dismissKeyboard();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = _storeName.text.trim();
    if (name.isEmpty) {
      showErrorDialog(context, '매장 이름을 적어주세요.');
      return;
    }

    final wage = _wage.valueInt;
    if (wage <= 0) {
      showErrorDialog(context, '시급을 입력해 주세요.');
      return;
    }

    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    final ok = await _confirmSummary(name: name, wage: wage, preview: preview);
    if (!mounted) return;
    if (!ok) return;

    // ── 수정 모드: 돈 관련 변경 시 적용 시작일 선택
    DateTime? effectiveFrom;
    if (_isEdit) {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final wageChanged = _initialWage != null && wage != _initialWage;
      final taxChanged = _initialTax != null && _tax != _initialTax;
      final insChanged = _initialIns != null && _ins != _initialIns;
      final surchargeChanged = _initialSurcharge != null &&
          _surcharge != _initialSurcharge;

      DateTime? wageSurchargeFrom;
      DateTime? taxInsFrom;

      // 시급·가산정책: 달력으로 날짜 직접 선택
      if (wageChanged || surchargeChanged) {
        final picked = await cp.showSingleDatePickerDialog(
          context,
          initialDate: todayDate,
          firstDay: DateTime(2020),
          lastDay: todayDate.add(const Duration(days: 365)),
          title: '시급·가산정책 적용일',
        );
        if (!mounted) return;
        if (picked == null) return;
        wageSurchargeFrom = DateTime(picked.year, picked.month, picked.day);
      }

      // 세금·보험: 이번달/다음달 선택
      if (taxChanged || insChanged) {
        final picked = await _showMonthChoiceDialog(title: '세금·보험 적용 시작');
        if (!mounted) return;
        if (picked == null) return;
        taxInsFrom = picked;
      }

      if (wageChanged || surchargeChanged || taxChanged || insChanged) {
        final lines = <String>[];
        if (wageChanged || surchargeChanged) {
          final d = wageSurchargeFrom!;
          if (wageChanged) lines.add('· ${d.month}/${d.day}부터 시급이 적용됩니다.');
          if (surchargeChanged) lines.add('· ${d.month}/${d.day}부터 가산정책이 적용됩니다.');
        }
        if (taxChanged || insChanged) {
          final d = taxInsFrom!;
          lines.add('· ${d.month}월 ${d.day}일부터 세금·보험이 적용됩니다.');
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('적용 시작일 안내',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            content: Text(lines.join('\n\n'),
                style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소',
                    style: TextStyle(color: Color(0xFF6B7280))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('확인',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (confirmed != true) return;

        effectiveFrom = wageSurchargeFrom ?? taxInsFrom;
      }
    }

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
          effectiveFrom: effectiveFrom,
        );
        if (!mounted) return;
        _snack(effectiveFrom != null
            ? '${effectiveFrom.month}/${effectiveFrom.day}부터 적용돼요.'
            : '수정 완료!');
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
        showErrorDialog(context, '초대코드 생성에 실패했어요.');
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OwnerStoreCodeScreen(storeName: store.name, storeCode: code),
        ),
      );
      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '저장에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── helpers
  Future<DateTime?> _showMonthChoiceDialog({String title = '언제부터 적용할까요?'}) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, thisMonth),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Row(children: [
                  const Expanded(child: Text('이번 달부터', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Text('${thisMonth.month}월 1일', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
                ]),
              ),
            ),
            const Divider(height: 1),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, nextMonth),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Row(children: [
                  const Expanded(child: Text('다음 달부터', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Text('${nextMonth.month}월 1일', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
                ]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _policyToMap() => {
        'tax': {
          'enabled': _tax != pol.TaxConfig.none,
          'value': _taxToPolicyValue(_tax),
        },
        'insurance': {
          'enabled': _ins is! pol.InsuranceNone,
          'value': _insToPolicyValue(_ins),
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
    if (t is pol.TaxConfigCustomPercent) {
      return {'kind': 'customPercent', 'percent': t.percent};
    }
    return 'none';
  }

  dynamic _insToPolicyValue(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return 'employmentOnly';
    if (i is pol.InsuranceFour) return 'four';
    return 'none';
  }

  int _legacyPayDay(PayrollPolicy p) {
    // ✅ 실제 급여 지급일 = payRule.monthlyDay (예: 25일 지급)
    // monthlyStartDay는 정산 시작일(예: 1일)이므로 급여일로 쓰면 안 됨
    if (p.cycle == PayCycleType.monthly &&
        p.payRule.type == PayDateRuleType.nextMonthlyDay) {
      return (p.payRule.monthlyDay ?? 10).clamp(1, 31);
    }
    return 1;
  }

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
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _isEdit ? '수정' : '만들기',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
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
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: _textPrimary,
          ),
          onPressed: () {
            _dismissKeyboard();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          _isEdit ? '매장 수정' : '매장 만들기',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: _textPrimary,
          ),
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
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          children: [
            // ── ① 색상 + 매장명
            _FormCard(
              child: Row(
                children: [
                  // 색상 도트
                  GestureDetector(
                    onTap: () async {
                      _dismissKeyboard();
                      final picked = await cp.showColorPaletteDialog(
                        context: context,
                        initialHex: _colorHex,
                      );
                      if (!mounted) return;

                      if (picked != null) {
                        setState(() {
                          _colorHex = picked;
                          _color = cp.parseColor(picked);
                        });
                      }
                    },
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
                      child: const Icon(
                        Icons.palette_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _storeName,
                      focusNode: _storeNameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) {
                        FocusScope.of(context).requestFocus(_wageFocus);
                      },
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '매장 이름',
                        hintStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFD1D5DB),
                        ),
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
                      focusNode: _wageFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _dismissKeyboard(),
                      inputFormatters: [
                        MoneyTextController.digitsOnlyFormatter,
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
                          color: Color(0xFFE5E7EB),
                        ),
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
                  const Text(
                    '원',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
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
                    helpTitle: '세금이란?',
                    helpBody: '급여를 받을 때 국가에 내는 소득세예요.\n\n'
                        '• 없음 — 세금 없이 급여 전액을 받아요.\n\n'
                        '• 3.3% — 프리랜서·강사처럼 용역 계약으로 일할 때 써요. 급여의 3.3%를 세금으로 내요.\n\n'
                        '• 일용직 (6.6%) — 하루 단위 단기 알바에 써요. 하루 일당에서 15만 원을 먼저 빼고, 남은 금액의 2.97%만 세금으로 내요.\n'
                        '  예) 일당 20만 원 → 5만 원 × 2.97% ≈ 1,485원\n\n'
                        '• 직접 입력 — 세율을 직접 정할 수 있어요.',
                  ),
                  const SizedBox(height: 2),
                  _OwnerSettingRow(
                    icon: Icons.health_and_safety_outlined,
                    label: '보험',
                    value: _insLabel(_ins),
                    onTap: _openPolicy,
                    helpTitle: '4대보험이란?',
                    helpBody: '국가에서 운영하는 사회보험이에요. 일부 금액을 급여에서 공제해요.\n\n'
                        '• 없음 — 보험료를 공제하지 않아요.\n\n'
                        '• 고용보험만 (0.9%) — 급여의 0.9%를 공제해요. 나중에 직장을 잃으면 실업급여를 받을 수 있어요.\n\n'
                        '• 4대보험 전체 (~9.4%) — 국민연금 4.5% + 건강보험 3.545% + 고용보험 0.9% + 장기요양 0.45% = 약 9.4%를 공제해요.\n\n'
                        '※ 2026년 근로자 부담분 기준이에요.',
                  ),
                  const SizedBox(height: 2),
                  _OwnerSettingRow(
                    icon: Icons.nightlight_outlined,
                    label: '야간 · 연장 · 휴일',
                    value: _surchargeLabel(_surcharge),
                    onTap: _openPolicy,
                    helpTitle: '추가 수당이란?',
                    helpBody: '기본 시급 외에 법이나 약속으로 추가로 받는 돈이에요.\n\n'
                        '아래 각 항목의 ? 버튼을 누르면 계산 방법을 자세히 볼 수 있어요.',
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFF0F0F5)),
                  const SizedBox(height: 8),
                  _OwnerToggleRow(
                    icon: Icons.calendar_today_rounded,
                    label: '주휴수당',
                    desc: '주 15시간 이상 근무 시 1일치 급여 추가',
                    value: _surcharge.weeklyHolidayEnabled,
                    accent: _color,
                    onChanged: (v) => setState(() {
                      _surcharge =
                          _surcharge.copyWith(weeklyHolidayEnabled: v);
                    }),
                    helpTitle: '주휴수당이란?',
                    helpBody: '주 15시간 이상 일하면 쉬는 날에도 하루치 급여를 추가로 받는 제도예요.\n\n'
                        '계산법\n'
                        '(주 근무시간 ÷ 40시간) × 8시간 × 시급\n'
                        '(최대 8시간까지만 인정해요)\n\n'
                        '예) 주 20시간 근무, 시급 10,000원\n'
                        '→ (20 ÷ 40) × 8시간 × 10,000원 = 40,000원 추가\n\n'
                        '※ 주 15시간 미만이면 주휴수당이 없어요.',
                  ),
                  const SizedBox(height: 6),
                  _OwnerToggleRow(
                    icon: Icons.access_time_rounded,
                    label: '주 40시간 초과 연장수당',
                    desc: '한 주 40시간 넘으면 초과분 50% 추가',
                    value: _surcharge.overtimeEnabled &&
                        _surcharge.overtimeRule ==
                            pol.OvertimeRule.weeklyOver40,
                    accent: _color,
                    onChanged: (v) => setState(() {
                      _surcharge = _surcharge.copyWith(
                        overtimeEnabled: v,
                        overtimeRule: v
                            ? pol.OvertimeRule.weeklyOver40
                            : _surcharge.overtimeRule,
                      );
                    }),
                    helpTitle: '연장수당 (주 40시간 초과)란?',
                    helpBody: '일요일~토요일 한 주 동안 총 40시간을 넘게 일하면 초과분에 추가 수당을 받아요.\n\n'
                        '계산법\n'
                        '(주 총 근무시간 - 40시간) × 시급 × 설정 비율%\n\n'
                        '예) 주 45시간 근무, 시급 10,000원, 50% 설정\n'
                        '→ 초과 5시간 × 10,000원 × 50% = 25,000원 추가',
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
                child: Text(
                  '설정',
                  style: TextStyle(
                    color: _color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _payrollSummary(_payrollPolicy),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '이번 기간: ${_fmtYmd(preview.period.start)} ~ ${_fmtYmd(preview.period.end)}  '
                    '지급: ${_fmtYmd(preview.payDate)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textTertiary,
                    ),
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
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _saving ? '저장하는 중…' : (_isEdit ? '수정 완료' : '매장 만들고 초대코드 받기'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
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

class _OwnerToggleRow extends StatelessWidget {
  const _OwnerToggleRow({
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.helpTitle,
    this.helpBody,
  });

  final IconData icon;
  final String label;
  final String desc;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final String? helpTitle;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value ? accent.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: value ? accent : const Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: value ? accent : const Color(0xFF374151),
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: value
                        ? accent.withOpacity(0.7)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          if (helpTitle != null) ...[
            helpIcon(context, title: helpTitle!, body: helpBody!),
            const SizedBox(width: 4),
          ],
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

String _formatMoneyText(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final noLeading = digits.replaceFirst(RegExp(r'^0+'), '');
  if (noLeading.isEmpty) return '';
  final v = int.tryParse(noLeading) ?? 0;
  return _commaFmt(v);
}
