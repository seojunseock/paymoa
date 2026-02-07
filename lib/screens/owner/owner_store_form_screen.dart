// lib/screens/owner/owner_store_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../policies/policies.dart' as pol;
import '../../policies/policy_sheet.dart';
import '../../data/store_repository.dart';

import '../../common/ui/app_card.dart';
import '../../common/ui/money_text_controller.dart';
import '../../common/ui/bottom_cta.dart';

// ✅ payroll
import '../../payroll/payroll.dart';
import '../../payroll/payroll_policy_mapper.dart'
    as ppm; // ✅ FIX: mapper는 직접 import

import '../payroll_policy_sheet.dart';

// ✅ 코드 화면
import 'owner_store_code_screen.dart';

class OwnerStoreFormScreen extends StatefulWidget {
  const OwnerStoreFormScreen({super.key});

  @override
  State<OwnerStoreFormScreen> createState() => _OwnerStoreFormScreenState();
}

class _OwnerStoreFormScreenState extends State<OwnerStoreFormScreen> {
  final _storeName = TextEditingController();
  late final MoneyTextController _wage;

  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy _surcharge = const pol.SurchargePolicy();

  bool _taxEnabled = false;
  bool _insEnabled = false;
  bool _surchargeEnabled = false;

  bool _saving = false;

  late PayrollPolicy _payrollPolicy;

  final _repo = StoreRepository();

  @override
  void initState() {
    super.initState();
    _wage = MoneyTextController();

    final now = DateTime.now();
    _payrollPolicy = PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: DateTime(now.year, now.month, now.day),
      monthlyStartDay: 1,
      payRule: const PayDateRule.nextMonthlyDay(10),
    );
  }

  @override
  void dispose() {
    _storeName.dispose();
    _wage.dispose();
    super.dispose();
  }

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

        if (r.tax != pol.TaxConfig.none) _taxEnabled = true;
        if (r.ins is! pol.InsuranceNone) _insEnabled = true;
        if (r.surcharge != null) _surchargeEnabled = true;
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
      setState(() {
        _payrollPolicy = _normalizeToMvpPolicies(res);
      });
    }
  }

  PayrollPolicy _normalizeToMvpPolicies(PayrollPolicy p) {
    final now = DateTime.now();
    final baseStart = DateTime(now.year, now.month, now.day);

    if (p.cycle == PayCycleType.daily) {
      return p.copyWith(
        startFrom:
            DateTime(p.startFrom.year, p.startFrom.month, p.startFrom.day),
      );
    }

    if (p.cycle == PayCycleType.monthly) {
      final msd = (p.monthlyStartDay ?? 1).clamp(1, 31);
      return p.copyWith(
        startFrom:
            DateTime(p.startFrom.year, p.startFrom.month, p.startFrom.day),
        monthlyStartDay: msd,
      );
    }

    return PayrollPolicy(
      cycle: PayCycleType.monthly,
      startFrom: baseStart,
      monthlyStartDay: 1,
      payRule: p.payRule,
    );
  }

  dynamic _taxToPolicyValue(pol.TaxConfig t) {
    if (t == pol.TaxConfig.none) return 'none';
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

  Map<String, dynamic> _policyToMap() {
    return {
      'tax': <String, dynamic>{
        'enabled': _taxEnabled,
        'value': _taxToPolicyValue(_tax),
      },
      'insurance': <String, dynamic>{
        'enabled': _insEnabled,
        'value': _insToPolicyValue(_ins),
      },
      'surcharge': <String, dynamic>{
        'enabled': _surchargeEnabled,
        'weeklyHolidayEnabled': _surcharge.weeklyHolidayEnabled,
        'overtimeEnabled': _surcharge.overtimeEnabled,
        'overtimePercent': _surcharge.overtimePercent,
        'holidayEnabled': _surcharge.holidayEnabled,
        'holidayPercent': _surcharge.holidayPercent,
        'nightEnabled': _surcharge.nightEnabled,
        'nightPercent': _surcharge.nightPercent,
      },

      // ✅ FIX: mapper는 payroll.dart에서 export하지 않음 → 직접 import한 ppm 사용
      'payrollPolicy': ppm.payrollPolicyToMap(_payrollPolicy),
    };
  }

  int _legacyPayDayFromPolicy(PayrollPolicy p) {
    if (p.cycle == PayCycleType.monthly) {
      return (p.monthlyStartDay ?? 1).clamp(1, 31);
    }
    return 1;
  }

  String _fmtYmd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _payrollSummaryLine(PayrollPolicy p) {
    String typeLabel() {
      if (p.cycle == PayCycleType.daily) return '하루씩 따로 계산하기(일급)';
      if (p.cycle == PayCycleType.monthly) {
        final msd = (p.monthlyStartDay ?? 1).clamp(1, 31);
        if (msd == 1) return '한 달(1일~말일)로 묶기';
        return '매달 같은 날 기준으로 묶기 (매달 $msd일 시작)';
      }
      return '급여 방식';
    }

    String payRuleLabel() {
      switch (p.payRule.type) {
        case PayDateRuleType.nextMonthlyDay:
          return '마감 후, 매달 ${p.payRule.monthlyDay ?? 10}일에 지급';
        case PayDateRuleType.samePeriodEndDay:
          return '마감하는 날에 바로 지급';
        case PayDateRuleType.afterEndPlusDays:
          return '마감하고 ${p.payRule.plusDays ?? 0}일 뒤에 지급';
        case PayDateRuleType.fixedDate:
          return '지정한 날짜에 지급';
      }
    }

    return '${typeLabel()} · ${payRuleLabel()}';
  }

  Future<bool> _confirmSummary({
    required String name,
    required int wage,
    required PeriodPayPreview preview,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이대로 만들까요?'),
        content: Text(
          '매장 이름: $name\n'
          '시급: ${_comma(wage)}원\n\n'
          '급여 방식: ${_payrollSummaryLine(_payrollPolicy)}\n'
          '이번엔 이렇게 계산돼요: ${_fmtYmd(preview.period.start)} ~ ${_fmtYmd(preview.period.end)} / 지급일 ${_fmtYmd(preview.payDate)}\n\n'
          '만들면 초대코드가 나와요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _submit() async {
    if (_saving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('로그인이 필요해요.')));
      return;
    }

    final name = _storeName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('매장 이름을 적어주세요.')));
      return;
    }

    final wage = _wage.valueInt;
    if (wage <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('시급을 적어주세요.')));
      return;
    }

    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    final ok = await _confirmSummary(name: name, wage: wage, preview: preview);
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final store = await _repo.createStore(
        uid: user.uid,
        name: name,
        defaultHourlyWage: wage,
        payDay: _legacyPayDayFromPolicy(_payrollPolicy),
        policy: _policyToMap(),
      );

      if (!mounted) return;

      final code = store.storeCode;
      if (code == null || code.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대코드를 만들지 못했어요.')),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OwnerStoreCodeScreen(
            storeName: store.name,
            storeCode: code,
          ),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장에 실패했어요: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = const PayrollEngine()
        .previewNext(policy: _payrollPolicy, count: 1)
        .first;

    String _stateText(bool on) => on ? '켬' : '끔';

    return Scaffold(
      appBar: AppBar(
        title: const Text('매장 만들기'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? '저장하는 중…' : '완료'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            title: '매장 정보',
            child: Column(
              children: [
                TextField(
                  controller: _storeName,
                  decoration: const InputDecoration(labelText: '매장 이름'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _wage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyTextController.digitsOnlyFormatter],
                  decoration: const InputDecoration(
                    labelText: '기본 시급',
                    hintText: '예: 10030',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: '공제/수당 설정',
            trailing: TextButton(
              onPressed: _openPolicy,
              child: const Text('바꾸기'),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('세금 떼기'),
                  subtitle: Text('상태: ${_stateText(_taxEnabled)}'),
                  value: _taxEnabled,
                  onChanged: (v) => setState(() => _taxEnabled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('보험 적용'),
                  subtitle: Text('상태: ${_stateText(_insEnabled)}'),
                  value: _insEnabled,
                  onChanged: (v) => setState(() => _insEnabled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('추가수당(야간/연장/휴일/주휴)'),
                  subtitle: Text('상태: ${_stateText(_surchargeEnabled)}'),
                  value: _surchargeEnabled,
                  onChanged: (v) => setState(() => _surchargeEnabled = v),
                ),
                const SizedBox(height: 6),
                Text(
                  '끔으로 두면 계산에 반영하지 않아요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.65),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: '급여 방식(필수)',
            trailing: TextButton(
              onPressed: _openPayrollPolicy,
              child: const Text('설정하기'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_payrollSummaryLine(_payrollPolicy)),
                const SizedBox(height: 6),
                Text(
                  '예시: ${_fmtYmd(preview.period.start)} ~ ${_fmtYmd(preview.period.end)} / 지급일 ${_fmtYmd(preview.payDate)}',
                ),
                const SizedBox(height: 8),
                Text(
                  '예시는 마지막 확인에서만 보여줘요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.65),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomCta(
        onPressed: _submit,
        enabled: !_saving,
        icon: Icons.add,
        label: _saving ? '저장하는 중…' : '만들고 초대코드 받기',
      ),
    );
  }
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
