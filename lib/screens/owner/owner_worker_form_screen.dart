// lib/screens/owner/owner_worker_form_screen.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../common/ui/app_card.dart';
import '../../common/ui/money_text_controller.dart';
import '../../common/ui/bottom_cta.dart';

import '../../data/worker_repository.dart';

import '../../policies/policies.dart' as pol;
import '../../policies/policy_mapper.dart' as pm;

class OwnerWorkerFormScreen extends StatefulWidget {
  const OwnerWorkerFormScreen({
    super.key,
    required this.store,
    required this.worker,
  });

  final Store store;
  final StoreWorker worker;

  @override
  State<OwnerWorkerFormScreen> createState() => _OwnerWorkerFormScreenState();
}

class _OwnerWorkerFormScreenState extends State<OwnerWorkerFormScreen> {
  final _nameCtrl = TextEditingController();
  late final MoneyTextController _wageCtrl;

  bool _loading = true;
  bool _saving = false;

  bool _inheritFromStore = true;
  int _payDay = 25;

  bool _taxEnabled = false;
  pol.TaxConfig _tax = pol.TaxConfig.none;
  double _customTaxPercent = 3.3;

  bool _insEnabled = false;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();

  bool _surchargeEnabled = false;

  bool _weeklyHolidayEnabled = false;

  bool _overtimeEnabled = false;
  int _overtimePercent = 50;

  bool _holidayEnabled = false;
  int _holidayPercent = 50;

  bool _nightEnabled = false;
  int _nightPercent = 50;

  Map<String, dynamic> _rawPolicyOverride = {};

  final _repo = WorkerRepository();

  String get _ownerUid => widget.store.ownerUid;
  String get _storeId => widget.store.id;
  String get _workerUid => widget.worker.workerUid;

  DocumentReference<Map<String, dynamic>> get _workerDoc =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_ownerUid)
          .collection('stores')
          .doc(_storeId)
          .collection('workers')
          .doc(_workerUid);

  @override
  void initState() {
    super.initState();
    _wageCtrl = MoneyTextController();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wageCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final snap = await _workerDoc.get();
      final m = snap.data() ?? <String, dynamic>{};

      final displayName =
          (m['displayName'] as String?) ?? (widget.worker.displayName ?? '');
      _nameCtrl.text = displayName;

      final inherit = (m['inheritFromStore'] as bool?) ?? true;
      _inheritFromStore = inherit;

      final storePayDay = (widget.store.payDay ?? 25).clamp(1, 31);
      final payDay = _toInt(m['payDay']) ?? storePayDay;
      _payDay = payDay.clamp(1, 31);

      final storeWage = widget.store.defaultHourlyWage ?? 0;
      final wage = _toInt(m['hourlyWage']) ?? storeWage;
      _setMoney(_wageCtrl, wage);

      final po = (m['policyOverride'] is Map)
          ? (m['policyOverride'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      _rawPolicyOverride = po;

      final (taxEnabled, taxConfig, customPct) = _readTax(po['tax']);
      _taxEnabled = taxEnabled;
      _tax = taxConfig;
      _customTaxPercent = customPct;

      final (insEnabled, insConfig) =
          _readInsurance(po['insurance'] ?? po['ins']);
      _insEnabled = insEnabled;
      _ins = insConfig;

      final surcharge = (po['surcharge'] is Map)
          ? (po['surcharge'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      _surchargeEnabled = surcharge['enabled'] == true;

      _weeklyHolidayEnabled = surcharge['weeklyHolidayEnabled'] == true;

      _overtimeEnabled = surcharge['overtimeEnabled'] == true;
      _overtimePercent =
          (_toInt(surcharge['overtimePercent']) ?? 50).clamp(0, 300);

      _holidayEnabled = surcharge['holidayEnabled'] == true;
      _holidayPercent =
          (_toInt(surcharge['holidayPercent']) ?? 50).clamp(0, 300);

      _nightEnabled = surcharge['nightEnabled'] == true;
      _nightPercent = (_toInt(surcharge['nightPercent']) ?? 50).clamp(0, 300);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('불러오지 못했어요: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyUid() async {
    await Clipboard.setData(ClipboardData(text: _workerUid));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('복사했어요.')));
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('네'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _endWorker() async {
    final ok = await _confirm(
      context,
      '이 직원을 종료할까요?',
    );
    if (!ok) return;

    try {
      await _repo.endWorker(
        ownerUid: _ownerUid,
        storeId: _storeId,
        workerUid: _workerUid,
        reason: 'kicked',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('완료했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('실패했어요: $e')));
    }
  }

  Map<String, dynamic> _buildPolicyOverrideMerged() {
    final out = Map<String, dynamic>.from(_rawPolicyOverride);

    out['tax'] = _buildTaxMap();
    out['insurance'] = _buildInsuranceMap();

    out['surcharge'] = <String, dynamic>{
      'enabled': _surchargeEnabled,
      'weeklyHolidayEnabled': _weeklyHolidayEnabled,
      'overtimeEnabled': _overtimeEnabled,
      'overtimePercent': _overtimePercent,
      'holidayEnabled': _holidayEnabled,
      'holidayPercent': _holidayPercent,
      'nightEnabled': _nightEnabled,
      'nightPercent': _nightPercent,
    };

    return out;
  }

  Map<String, dynamic> _buildTaxMap() {
    dynamic value;
    String kind;

    if (_tax is pol.TaxConfigCustomPercent) {
      value = {'kind': 'customPercent', 'percent': _customTaxPercent};
      kind = 'custom';
    } else if (_tax == pol.TaxConfig.biz33) {
      value = 'biz33';
      kind = 'biz33';
    } else if (_tax == pol.TaxConfig.day66) {
      value = 'day66';
      kind = 'day66';
    } else {
      value = 'none';
      kind = 'none';
    }

    return <String, dynamic>{
      'enabled': _taxEnabled,
      'kind': kind,
      'value': value,
    };
  }

  Map<String, dynamic> _buildInsuranceMap() {
    dynamic value;
    String kind;

    if (_ins is pol.InsuranceEmploymentOnly) {
      value = 'employmentOnly';
      kind = 'employmentOnly';
    } else if (_ins is pol.InsuranceFour) {
      value = 'four';
      kind = 'four';
    } else {
      value = 'none';
      kind = 'none';
    }

    return <String, dynamic>{
      'enabled': _insEnabled,
      'kind': kind,
      'value': value,
    };
  }

  Future<void> _save() async {
    if (_saving) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이름을 적어주세요.')));
      return;
    }

    final wage = _wageCtrl.valueInt;
    if (!_inheritFromStore && wage <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('따로 설정할 땐 시급을 적어주세요.')),
      );
      return;
    }

    if (!_inheritFromStore &&
        _taxEnabled &&
        _tax is pol.TaxConfigCustomPercent) {
      if (_customTaxPercent < 0 || _customTaxPercent > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('세금 비율은 0~100 사이로 적어주세요.')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await _repo.saveWorkerSettings(
        ownerUid: _ownerUid,
        storeId: _storeId,
        workerUid: _workerUid,
        displayName: name,
        inheritFromStore: _inheritFromStore,
        hourlyWage: _inheritFromStore ? null : wage,
        payDay: _inheritFromStore ? null : _payDay,
        policyOverride: _inheritFromStore ? null : _buildPolicyOverrideMerged(),
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

  Widget _percentField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    required bool enabled,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 92,
          child: TextFormField(
            enabled: enabled,
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (s) => onChanged((_toInt(s) ?? value).clamp(0, 300)),
            decoration: const InputDecoration(
              suffixText: '%',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _doublePercentField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required bool enabled,
  }) {
    final ctrl = TextEditingController(text: _fmtPct(value));
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 110,
          child: TextFormField(
            enabled: enabled,
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (s) {
              final v = double.tryParse(s.trim());
              if (v == null) return;
              onChanged(v);
            },
            decoration: const InputDecoration(
              suffixText: '%',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  String _fmtPct(double v) {
    final isInt = (v % 1 == 0);
    return v.toStringAsFixed(isInt ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final storeWage = widget.store.defaultHourlyWage ?? 0;
    final storePayDay = (widget.store.payDay ?? 25).clamp(1, 31);

    final canEditWorker = !_inheritFromStore;
    final canEditTax = canEditWorker && _taxEnabled;
    final canEditIns = canEditWorker && _insEnabled;
    final canEditSurcharge = canEditWorker && _surchargeEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('직원 설정'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '직원 종료',
            onPressed: _loading || _saving ? null : _endWorker,
            icon: const Icon(Icons.person_off_outlined),
          ),
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: Text(_saving ? '저장하는 중…' : '저장'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                  title: '기본 정보',
                  trailing: IconButton(
                    tooltip: '아이디 복사',
                    onPressed: _copyUid,
                    icon: const Icon(Icons.copy),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '이름',
                          hintText: '예: 홍길동',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('매장 설정 그대로'),
                        subtitle: Text(_inheritFromStore
                            ? '켜면 매장 설정을 그대로 써요.'
                            : '끄면 이 직원만 따로 설정해요.'),
                        value: _inheritFromStore,
                        onChanged: (v) {
                          setState(() {
                            _inheritFromStore = v;
                            if (v) {
                              _taxEnabled = false;
                              _insEnabled = false;
                              _surchargeEnabled = false;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  title: '시급/공제/수당',
                  child: Column(
                    children: [
                      TextField(
                        controller: _wageCtrl,
                        enabled: canEditWorker,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          MoneyTextController.digitsOnlyFormatter
                        ],
                        decoration: InputDecoration(
                          labelText: '시급',
                          helperText: _inheritFromStore
                              ? '매장 시급: ${_comma(storeWage)}원'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Expanded(child: Text('매달 지급일')),
                          DropdownButton<int>(
                            value: _payDay,
                            onChanged: canEditWorker
                                ? (v) {
                                    if (v == null) return;
                                    setState(() => _payDay = v);
                                  }
                                : null,
                            items: List.generate(
                              31,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('${i + 1}일'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_inheritFromStore)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '매장 지급일: 매달 $storePayDay일',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _taxEnabled,
                        onChanged: canEditWorker
                            ? (v) => setState(() => _taxEnabled = v)
                            : null,
                        title: const Text('세금 떼기'),
                        subtitle: Text(_taxEnabled
                            ? '세금을 계산에 반영해요.'
                            : '세금은 계산에 반영하지 않아요.'),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Expanded(child: Text('세금 종류')),
                          DropdownButton<String>(
                            value: _taxDropdownValue(_tax),
                            onChanged: canEditTax
                                ? (v) {
                                    if (v == null) return;
                                    setState(() {
                                      _tax = _taxFromDropdown(
                                          v, _customTaxPercent);
                                      if (_tax is pol.TaxConfigCustomPercent) {
                                        _customTaxPercent =
                                            max(0.0, _customTaxPercent);
                                      }
                                    });
                                  }
                                : null,
                            items: const [
                              DropdownMenuItem(
                                  value: 'none', child: Text('없음')),
                              DropdownMenuItem(
                                  value: 'biz33', child: Text('3.3%')),
                              DropdownMenuItem(
                                  value: 'day66', child: Text('6.6%')),
                              DropdownMenuItem(
                                  value: 'custom', child: Text('직접 적기')),
                            ],
                          ),
                        ],
                      ),
                      if ((_tax is pol.TaxConfigCustomPercent))
                        _doublePercentField(
                          label: '세금 비율',
                          value: _customTaxPercent,
                          enabled: canEditTax,
                          onChanged: (v) =>
                              setState(() => _customTaxPercent = v),
                        ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _insEnabled,
                        onChanged: canEditWorker
                            ? (v) => setState(() => _insEnabled = v)
                            : null,
                        title: const Text('보험 적용'),
                        subtitle: Text(_insEnabled
                            ? '보험을 계산에 반영해요.'
                            : '보험은 계산에 반영하지 않아요.'),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Expanded(child: Text('보험 종류')),
                          DropdownButton<String>(
                            value: _insDropdownValue(_ins),
                            onChanged: canEditIns
                                ? (v) {
                                    if (v == null) return;
                                    setState(() => _ins = _insFromDropdown(v));
                                  }
                                : null,
                            items: const [
                              DropdownMenuItem(
                                  value: 'none', child: Text('없음')),
                              DropdownMenuItem(
                                  value: 'employmentOnly', child: Text('고용보험')),
                              DropdownMenuItem(
                                  value: 'four', child: Text('4대보험')),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _surchargeEnabled,
                        onChanged: canEditWorker
                            ? (v) => setState(() => _surchargeEnabled = v)
                            : null,
                        title: const Text('추가수당 적용'),
                        subtitle: Text(_surchargeEnabled
                            ? '추가수당을 계산에 반영해요.'
                            : '추가수당은 계산에 반영하지 않아요.'),
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _weeklyHolidayEnabled,
                        onChanged: canEditSurcharge
                            ? (v) => setState(() => _weeklyHolidayEnabled = v)
                            : null,
                        title: const Text('주휴수당'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _overtimeEnabled,
                        onChanged: canEditSurcharge
                            ? (v) => setState(() => _overtimeEnabled = v)
                            : null,
                        title: const Text('연장수당'),
                      ),
                      _percentField(
                        label: '연장 비율',
                        value: _overtimePercent,
                        enabled: canEditSurcharge && _overtimeEnabled,
                        onChanged: (v) => setState(() => _overtimePercent = v),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _holidayEnabled,
                        onChanged: canEditSurcharge
                            ? (v) => setState(() => _holidayEnabled = v)
                            : null,
                        title: const Text('휴일수당'),
                      ),
                      _percentField(
                        label: '휴일 비율',
                        value: _holidayPercent,
                        enabled: canEditSurcharge && _holidayEnabled,
                        onChanged: (v) => setState(() => _holidayPercent = v),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _nightEnabled,
                        onChanged: canEditSurcharge
                            ? (v) => setState(() => _nightEnabled = v)
                            : null,
                        title: const Text('야간수당'),
                      ),
                      _percentField(
                        label: '야간 비율',
                        value: _nightPercent,
                        enabled: canEditSurcharge && _nightEnabled,
                        onChanged: (v) => setState(() => _nightPercent = v),
                      ),
                      if (_inheritFromStore)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '매장 설정 그대로 상태라 이 직원만의 값은 저장하지 않아요.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: BottomCta(
        enabled: !_saving && !_loading,
        onPressed: () => _save(),
        icon: Icons.save,
        label: _saving ? '저장하는 중…' : '저장',
      ),
    );
  }

  (bool enabled, pol.TaxConfig config, double customPct) _readTax(dynamic raw) {
    bool enabled = false;
    pol.TaxConfig cfg = pol.TaxConfig.none;
    double customPct = 3.3;

    if (raw == null) return (enabled, cfg, customPct);

    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      if (m.containsKey('enabled') || m.containsKey('value')) {
        enabled = (m['enabled'] == true);
        final v = m.containsKey('value') ? m['value'] : m['kind'];

        cfg = pm.taxConfigFromAny(v);
        if (cfg is pol.TaxConfigCustomPercent) {
          customPct = max(0.0, cfg.percent);
          cfg = pol.TaxConfigCustomPercent(customPct);
        }
        return (enabled, cfg, customPct);
      }
    }

    cfg = pm.taxConfigFromAny(raw);
    enabled = (cfg != pol.TaxConfig.none);
    if (cfg is pol.TaxConfigCustomPercent) {
      customPct = max(0.0, cfg.percent);
      cfg = pol.TaxConfigCustomPercent(customPct);
    }
    return (enabled, cfg, customPct);
  }

  (bool enabled, pol.InsuranceConfig config) _readInsurance(dynamic raw) {
    bool enabled = false;
    pol.InsuranceConfig cfg = const pol.InsuranceNone();

    if (raw == null) return (enabled, cfg);

    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      if (m.containsKey('enabled') || m.containsKey('value')) {
        enabled = (m['enabled'] == true);
        final v = m.containsKey('value') ? m['value'] : m['kind'];
        cfg = pm.insuranceConfigFromAny(v);
        return (enabled, cfg);
      }
    }

    cfg = pm.insuranceConfigFromAny(raw);
    enabled = !(cfg is pol.InsuranceNone);
    return (enabled, cfg);
  }

  String _taxDropdownValue(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return 'biz33';
    if (t == pol.TaxConfig.day66) return 'day66';
    if (t is pol.TaxConfigCustomPercent) return 'custom';
    return 'none';
  }

  pol.TaxConfig _taxFromDropdown(String v, double customPct) {
    switch (v) {
      case 'biz33':
        return pol.TaxConfig.biz33;
      case 'day66':
        return pol.TaxConfig.day66;
      case 'custom':
        return pol.TaxConfigCustomPercent(customPct);
      case 'none':
      default:
        return pol.TaxConfig.none;
    }
  }

  String _insDropdownValue(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return 'employmentOnly';
    if (i is pol.InsuranceFour) return 'four';
    return 'none';
  }

  pol.InsuranceConfig _insFromDropdown(String v) {
    switch (v) {
      case 'employmentOnly':
        return const pol.InsuranceEmploymentOnly();
      case 'four':
        return const pol.InsuranceFour();
      case 'none':
      default:
        return const pol.InsuranceNone();
    }
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

void _setMoney(TextEditingController c, int v) {
  c.text = _comma(v);
  c.selection = TextSelection.collapsed(offset: c.text.length);
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
