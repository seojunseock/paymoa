// lib/screens/owner/owner_worker_form_screen.dart
// ✅ store form과 완전 동일한 디자인 패턴으로 통일
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../common/paymoa_design.dart';
import '../../common/common_pickers.dart' as cp;
import '../date_assign_sheet.dart';
import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../models/store_schedule.dart';
import '../../common/ui/money_text_controller.dart';
import '../../data/firebase_service.dart';
import '../../policies/policies.dart' as pol;
import '../../policies/policy_sheet.dart';
import '../../policies/policy_mapper.dart' as pm;

const _bg = Color(0xFFF8F7FF);
const _textPrimary = Pm.textPrimary;
const _textSecondary = Pm.textSecondary;
const _textTertiary = Pm.textTertiary;

/* ─── _FormCard (store form 완전 동일) ─── */
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
            Row(children: [
              Text(label!,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textTertiary,
                      letterSpacing: 0.5)),
              const Spacer(),
              if (trailing != null) trailing!,
            ]),
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

/* ─── _SettingRow (store form _OwnerSettingRow 동일) ─── */
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
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
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF))),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
          ]),
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════
   직원 설정 폼
   ═══════════════════════════════════════════ */
class OwnerWorkerFormScreen extends StatefulWidget {
  const OwnerWorkerFormScreen({
    super.key,
    required this.store,
    required this.worker,
    this.workerSchedules = const [], // ✅ effectiveFrom 스케줄 일괄 적용용
  });
  final Store store;
  final StoreWorker worker;
  final List<StoreSchedule> workerSchedules;
  @override
  State<OwnerWorkerFormScreen> createState() => _OwnerWorkerFormScreenState();
}

class _OwnerWorkerFormScreenState extends State<OwnerWorkerFormScreen> {
  final _nameCtrl = TextEditingController();
  late final MoneyTextController _wageCtrl;

  bool _loading = true;
  bool _saving = false;
  bool _formattingWage = false;
  bool _inheritFromStore = true;

  int? _initialWage; // ✅ 저장 전 기존 시급
  pol.SurchargePolicy? _initialSurcharge; // ✅ 저장 전 기존 정책 (변경 감지용)

  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy _surcharge = const pol.SurchargePolicy();
  Map<String, dynamic> _rawPolicyOverride = {};

  final _repo = FirebaseService();

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
    _wageCtrl.addListener(() {
      if (_formattingWage) return;
      final txt = _wageCtrl.text;
      final fmt = _formatMoneyText(txt);
      if (fmt != txt) {
        _formattingWage = true;
        _wageCtrl.value = TextEditingValue(
          text: fmt,
          selection: TextSelection.collapsed(offset: fmt.length),
        );
        _formattingWage = false;
      }
    });
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
      _nameCtrl.text =
          (m['displayName'] as String?) ?? (widget.worker.displayName ?? '');
      _inheritFromStore = (m['inheritFromStore'] as bool?) ?? true;
      final storeWage = widget.store.defaultHourlyWage ?? 0;
      final loadedWage = _toInt(m['hourlyWage']) ?? storeWage;
      _wageCtrl.setValueInt(loadedWage);
      _initialWage = loadedWage; // ✅ 기존 시급 기록
      final po = (m['policyOverride'] is Map)
          ? (m['policyOverride'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      _rawPolicyOverride = po;
      final (_, taxCfg, _) = _readTax(po['tax']);
      _tax = taxCfg;
      final (_, insCfg) = _readInsurance(po['insurance'] ?? po['ins']);
      _ins = insCfg;
      _surcharge = _readSurcharge(po['surcharge']);
      _initialSurcharge = _surcharge; // ✅ 초기 정책 기록
    } catch (e) {
      if (mounted) _snack('불러오지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      });
    }
  }

  /// 가산정책이 바뀌었는지 비교
  bool _policyChanged() {
    final before = _initialSurcharge;
    final after = _surcharge;
    if ((before?.weeklyHolidayEnabled ?? false) != after.weeklyHolidayEnabled)
      return true;
    if ((before?.overtimeEnabled ?? false) != after.overtimeEnabled)
      return true;
    if ((before?.overtimePercent ?? 0) != after.overtimePercent) return true;
    if ((before?.overtimeRule ?? pol.OvertimeRule.dailyOver8) !=
        after.overtimeRule) return true;
    if ((before?.holidayEnabled ?? false) != after.holidayEnabled) return true;
    if ((before?.holidayPercent ?? 0) != after.holidayPercent) return true;
    if ((before?.nightEnabled ?? false) != after.nightEnabled) return true;
    if ((before?.nightPercent ?? 0) != after.nightPercent) return true;
    return false;
  }

  Future<DateTime?> _showPolicyDateDialog() async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    int? selected;
    DateTime? customDate;

    String _fmt(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('수당 정책 변경 적용',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              SizedBox(height: 6),
              Text('언제부터 적용할까요?',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DateOptionTile(
                label: '오늘부터',
                sublabel: '${_fmt(todayDate)} 이후 모든 근무에 적용',
                selected: selected == 0,
                onTap: () => ss(() => selected = 0),
              ),
              const SizedBox(height: 8),
              _DateOptionTile(
                label: '날짜 선택',
                sublabel: customDate != null
                    ? '${_fmt(customDate!)}부터 적용'
                    : '적용할 시작 날짜를 선택하세요',
                selected: selected == 1,
                onTap: () async {
                  // ✅ 알바생 근무 추가 달력과 동일한 UI 사용
                  final result = await showDateAssignSheet(
                    ctx,
                    existing: const {},
                    checkConflict: (_) => false,
                    focusedDay: customDate ?? todayDate,
                  );
                  if (result != null && result.selectedDates.isNotEmpty) {
                    final picked = result.selectedDates.first;
                    ss(() {
                      selected = 1;
                      customDate =
                          DateTime(picked.year, picked.month, picked.day);
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소',
                  style: TextStyle(
                      color: Pm.textSecondary, fontWeight: FontWeight.w500)),
            ),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(
                        ctx,
                        selected == 0 ? todayDate : (customDate ?? todayDate),
                      ),
              child: const Text('확인',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Pm.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('이름을 적어주세요.');
      return;
    }
    final wage = _wageCtrl.valueInt;
    if (!_inheritFromStore && wage <= 0) {
      _snack('따로 설정할 땐 시급을 입력해 주세요.');
      return;
    }

    DateTime? effectiveFrom;
    bool todayOnly = false;

    if (!_inheritFromStore) {
      final picked = await _showEffectiveDateDialog();
      if (!mounted) return;
      if (picked == null) return;
      effectiveFrom = picked.date;
      todayOnly = picked.todayOnly;
    } else {
      // ✅ 매장 기본값 상속 시: 팝업 없이 오늘 날짜를 자동으로 기준일로 기록
      // → policyHistory에 이력이 쌓여 날짜 기반 시급 계산이 정확해짐
      final now = DateTime.now();
      effectiveFrom = DateTime(now.year, now.month, now.day);
    }

    setState(() => _saving = true);
    try {
      final bool wageChanged =
          !_inheritFromStore && _initialWage != null && wage != _initialWage;

      // ✅ 핵심 수정: effectiveFrom이 미래 날짜인 경우
      // → storeJoins.hourlyWage를 즉시 새 시급으로 업데이트하면
      //   effectiveFrom 이전 스케줄에도 소급 적용되는 버그 발생
      // → 과거 스케줄에 oldWage를 overrideHourlyWage로 먼저 고정한 뒤 저장
      if (wageChanged &&
          widget.workerSchedules.isNotEmpty &&
          !todayOnly &&
          effectiveFrom != null) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        // ✅ 오늘부터 포함 (오늘 이전 스케줄도 구 시급으로 고정 필요)
        // isAfter → !isBefore: 오늘 = effectiveFrom인 경우도 처리
        if (!effectiveFrom.isBefore(todayDate)) {
          await _repo.bulkUpdateStoreScheduleWage(
            ownerUid: _ownerUid,
            storeId: _storeId,
            workerUid: _workerUid,
            newWage: _initialWage!, // 기존 시급으로 과거 스케줄 고정
            schedules: widget.workerSchedules,
            todayOnly: false,
            fromDate: DateTime(1970), // 전체 과거 스케줄
            untilDate: effectiveFrom, // effectiveFrom 직전까지
          );
        }
      }

      // ✅ 가산정책 변경 시 적용 날짜 팝업
      DateTime? policyEffectiveFrom;
      if (!_inheritFromStore && _policyChanged()) {
        if (!mounted) return;
        policyEffectiveFrom = await _showPolicyDateDialog();
        if (!mounted) return;
        if (policyEffectiveFrom == null) {
          setState(() => _saving = false); // ✅ 취소 시 버튼 다시 활성화
          return;
        }
      }

      await _repo.saveWorkerSettings(
        ownerUid: _ownerUid,
        storeId: _storeId,
        workerUid: _workerUid,
        displayName: name,
        inheritFromStore: _inheritFromStore,
        hourlyWage: _inheritFromStore ? null : wage,
        // ✅ 변경 전 시급 → policyHistory 이력 보존
        previousHourlyWage:
            (!_inheritFromStore && _initialWage != null && wage != _initialWage)
                ? _initialWage
                : null,
        policyOverride: _inheritFromStore ? null : _buildPolicyOverride(),
        effectiveFrom: effectiveFrom,
        policyEffectiveFrom: policyEffectiveFrom,
      );

      // ✅ effectiveFrom 이후 스케줄에 새 시급 일괄 적용
      if (!_inheritFromStore &&
          wage > 0 &&
          widget.workerSchedules.isNotEmpty &&
          (todayOnly || effectiveFrom != null)) {
        await _repo.bulkUpdateStoreScheduleWage(
          ownerUid: _ownerUid,
          storeId: _storeId,
          workerUid: _workerUid,
          newWage: wage,
          schedules: widget.workerSchedules,
          todayOnly: todayOnly,
          fromDate: todayOnly ? null : effectiveFrom,
        );
      }

      if (!mounted) return;
      if (effectiveFrom != null) {
        _snack(todayOnly
            ? '오늘 근무에만 적용됐어요.'
            : '${effectiveFrom.month}월 ${effectiveFrom.day}일부터 적용돼요.');
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<({DateTime date, bool todayOnly})?> _showEffectiveDateDialog() async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    // 0=오늘부터, 1=날짜로 적용
    int? selected;
    DateTime? customDate; // ✅ null로 시작 → 달력 초기 선택 없음

    return showDialog<({DateTime date, bool todayOnly})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Pm.radiusBtn)),
          title: const Text('언제부터 적용할까요?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('변경된 시급/정책이 이 날짜 이후 근무부터 적용돼요.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 16),
              _DateChip(
                label: '오늘부터',
                sublabel: '${now.month}/${now.day} 이후 모두',
                selected: selected == 0,
                onTap: () => setDlg(() => selected = 0),
              ),
              const SizedBox(height: 8),
              _DateChip(
                label: '날짜로 적용',
                sublabel: customDate != null
                    ? '${customDate!.year}/${customDate!.month}/${customDate!.day}부터'
                    : '날짜를 선택하세요',
                selected: selected == 1,
                isCustom: true,
                onTap: () async {
                  final result = await showDateAssignSheet(
                    ctx,
                    existing: const {}, // ✅ 빈 달력으로 시작 — 자동 선택 없음
                    checkConflict: (_) => false,
                    focusedDay: customDate ?? todayDate,
                  );
                  if (result != null && result.selectedDates.isNotEmpty) {
                    final p = result.selectedDates.first;
                    setDlg(() {
                      selected = 1;
                      customDate = DateTime(p.year, p.month, p.day);
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소',
                  style: TextStyle(
                      color: Pm.textSecondary, fontWeight: FontWeight.w500)),
            ),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () {
                      final date =
                          selected == 0 ? todayDate : (customDate ?? todayDate);
                      Navigator.pop(ctx, (date: date, todayOnly: false));
                    },
              child: const Text('적용',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Pm.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _endWorker() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알바생 내보내기'),
        content: const Text('이 알바생을 내보낼까요?\n근무 기록은 모두 보존돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(
                    color: Pm.textSecondary, fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('내보내기',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.endWorker(
        ownerUid: _ownerUid,
        storeId: _storeId,
        workerUid: _workerUid,
        reason: 'kicked',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeWage = widget.store.defaultHourlyWage ?? 0;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.worker.displayName?.isNotEmpty == true
              ? widget.worker.displayName!
              : '알바생 설정',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: _textPrimary),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '저장 중…' : '저장',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _saving ? _textTertiary : Pm.primary),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                // ① 알바생 이름
                _FormCard(
                  label: '알바생',
                  child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary),
                    decoration: const InputDecoration(
                      hintText: '이름',
                      hintStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFD1D5DB)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ② 설정 방식 (매장 그대로 / 개인 설정)
                _FormCard(
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _inheritFromStore
                              ? const Color(0xFFF3F4F6)
                              : Pm.primary.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _inheritFromStore
                              ? Icons.store_outlined
                              : Icons.person_outlined,
                          color: _inheritFromStore
                              ? const Color(0xFF9CA3AF)
                              : Pm.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _inheritFromStore ? '매장 설정 그대로' : '개인 설정',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _inheritFromStore
                                  ? '매장 기본 시급 · 세금 적용'
                                  : '이 알바생만 따로 설정',
                              style: const TextStyle(
                                  fontSize: 13, color: _textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !_inheritFromStore,
                        activeColor: Pm.primary,
                        onChanged: (v) {
                          setState(() {
                            _inheritFromStore = !v;
                            if (!v) {
                              _tax = pol.TaxConfig.none;
                              _ins = const pol.InsuranceNone();
                              _surcharge = const pol.SurchargePolicy();
                            } else {
                              _wageCtrl.setValueInt(storeWage);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ③ 시급 (store form 완전 동일 레이아웃)
                _FormCard(
                  label: '시급',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _wageCtrl,
                          enabled: !_inheritFromStore,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            MoneyTextController.digitsOnlyFormatter
                          ],
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _inheritFromStore
                                ? _textTertiary
                                : _textPrimary,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            hintText: _commaFmt(storeWage),
                            hintStyle: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFE5E7EB)),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '원',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _inheritFromStore
                                ? _textTertiary
                                : const Color(0xFF374151)),
                      ),
                    ],
                  ),
                ),

                if (_inheritFromStore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      '매장 기본 시급: ${_commaFmt(storeWage)}원 · 개인 설정 켜면 변경 가능',
                      style:
                          const TextStyle(fontSize: 12, color: _textTertiary),
                    ),
                  ),

                const SizedBox(height: 12),

                // ④ 세금 · 보험 · 가산 (store form 완전 동일)
                _FormCard(
                  label: '세금 · 보험 · 가산',
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.receipt_long_outlined,
                        label: '세금',
                        value: _taxLabel(_tax),
                        onTap: _openPolicy,
                        enabled: !_inheritFromStore,
                      ),
                      const SizedBox(height: 2),
                      _SettingRow(
                        icon: Icons.health_and_safety_outlined,
                        label: '보험',
                        value: _insLabel(_ins),
                        onTap: _openPolicy,
                        enabled: !_inheritFromStore,
                      ),
                      const SizedBox(height: 2),
                      _SettingRow(
                        icon: Icons.nightlight_outlined,
                        label: '야간 · 연장 · 휴일',
                        value: _surchargeLabel(_surcharge),
                        onTap: _openPolicy,
                        enabled: !_inheritFromStore,
                      ),
                    ],
                  ),
                ),

                if (_inheritFromStore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      '개인 설정을 켜면 이 알바생만 별도로 설정할 수 있어요.',
                      style:
                          const TextStyle(fontSize: 12, color: _textTertiary),
                    ),
                  ),

                const SizedBox(height: 32),

                // ⑤ 저장 버튼 (store form 완전 동일)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Pm.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Pm.radiusBtn)),
                    ),
                    child: Text(
                      _saving ? '저장하는 중…' : '저장',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white),
                    ),
                  ),
                ),

                // ⑥ 알바생 내보내기 (하단 파괴적 액션)
                if (!_loading) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: _endWorker,
                      icon: const Icon(Icons.logout_outlined,
                          size: 18, color: Color(0xFFF43F5E)),
                      label: const Text(
                        '알바생 내보내기',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF43F5E)),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF43F5E),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // ── 라벨
  String _taxLabel(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return '사업소득세 3.3%';
    if (t == pol.TaxConfig.day66) return '일용소득세 6.6%';
    if (t is pol.TaxConfigCustomPercent)
      return '${t.percent.toStringAsFixed(1)}%';
    return _inheritFromStore ? '매장 설정 따름' : '없음';
  }

  String _insLabel(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return '고용보험';
    if (i is pol.InsuranceFour) return '4대보험';
    return _inheritFromStore ? '매장 설정 따름' : '없음';
  }

  String _surchargeLabel(pol.SurchargePolicy s) {
    if (_inheritFromStore) return '매장 설정 따름';
    final parts = <String>[];
    if (s.overtimeEnabled) parts.add('연장');
    if (s.nightEnabled) parts.add('야간');
    if (s.holidayEnabled) parts.add('휴일');
    if (s.weeklyHolidayEnabled) parts.add('주휴');
    return parts.isEmpty ? '없음' : parts.join(' · ');
  }

  Map<String, dynamic> _buildPolicyOverride() {
    final out = Map<String, dynamic>.from(_rawPolicyOverride);
    out['tax'] = {
      'enabled': _tax != pol.TaxConfig.none,
      'value': _taxToValue(_tax),
    };
    out['insurance'] = {
      'enabled': _ins is! pol.InsuranceNone,
      'value': _insToValue(_ins),
    };
    out['surcharge'] = {
      'enabled': _surcharge.overtimeEnabled ||
          _surcharge.nightEnabled ||
          _surcharge.holidayEnabled ||
          _surcharge.weeklyHolidayEnabled,
      'weeklyHolidayEnabled': _surcharge.weeklyHolidayEnabled,
      'overtimeEnabled': _surcharge.overtimeEnabled,
      'overtimePercent': _surcharge.overtimePercent,
      'overtimeRule': _surcharge.overtimeRule == pol.OvertimeRule.weeklyOver40
          ? 'weeklyOver40'
          : 'dailyOver8',
      'holidayEnabled': _surcharge.holidayEnabled,
      'holidayPercent': _surcharge.holidayPercent,
      'nightEnabled': _surcharge.nightEnabled,
      'nightPercent': _surcharge.nightPercent,
    };
    return out;
  }

  dynamic _taxToValue(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return 'biz33';
    if (t == pol.TaxConfig.day66) return 'day66';
    if (t is pol.TaxConfigCustomPercent)
      return {'kind': 'customPercent', 'percent': t.percent};
    return 'none';
  }

  dynamic _insToValue(pol.InsuranceConfig i) {
    if (i is pol.InsuranceEmploymentOnly) return 'employmentOnly';
    if (i is pol.InsuranceFour) return 'four';
    return 'none';
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  (bool, pol.TaxConfig, double) _readTax(dynamic raw) {
    if (raw == null) return (false, pol.TaxConfig.none, 3.3);
    pol.TaxConfig cfg = pol.TaxConfig.none;
    bool enabled = false;
    double customPct = 3.3;
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      enabled = m['enabled'] == true;
      final v = m.containsKey('value') ? m['value'] : m['kind'];
      cfg = pm.taxConfigFromAny(v);
      if (cfg is pol.TaxConfigCustomPercent) customPct = max(0.0, cfg.percent);
      return (enabled, cfg, customPct);
    }
    cfg = pm.taxConfigFromAny(raw);
    enabled = cfg != pol.TaxConfig.none;
    if (cfg is pol.TaxConfigCustomPercent) customPct = max(0.0, cfg.percent);
    return (enabled, cfg, customPct);
  }

  (bool, pol.InsuranceConfig) _readInsurance(dynamic raw) {
    if (raw == null) return (false, const pol.InsuranceNone());
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      final enabled = m['enabled'] == true;
      final v = m.containsKey('value') ? m['value'] : m['kind'];
      return (enabled, pm.insuranceConfigFromAny(v));
    }
    final cfg = pm.insuranceConfigFromAny(raw);
    return (cfg is! pol.InsuranceNone, cfg);
  }

  pol.SurchargePolicy _readSurcharge(dynamic raw) {
    if (raw is! Map) return const pol.SurchargePolicy();
    final m = raw.cast<String, dynamic>();
    final ruleStr = (m['overtimeRule'] as String?)?.trim();
    final overtimeRule = ruleStr == 'weeklyOver40'
        ? pol.OvertimeRule.weeklyOver40
        : pol.OvertimeRule.dailyOver8;
    return pol.SurchargePolicy(
      weeklyHolidayEnabled: m['weeklyHolidayEnabled'] == true,
      overtimeEnabled: m['overtimeEnabled'] == true,
      overtimePercent: (_toInt(m['overtimePercent']) ?? 50).clamp(0, 300),
      overtimeRule: overtimeRule,
      holidayEnabled: m['holidayEnabled'] == true,
      holidayPercent: (_toInt(m['holidayPercent']) ?? 50).clamp(0, 300),
      nightEnabled: m['nightEnabled'] == true,
      nightPercent: (_toInt(m['nightPercent']) ?? 50).clamp(0, 300),
    );
  }
}

/* ─── 적용일 칩 ─── */
class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });
  final String label;
  final String sublabel;
  final bool selected;
  final bool isCustom;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected ? Pm.primary.withOpacity(0.07) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Pm.primary : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCustom
                  ? Icons.calendar_today_outlined
                  : Icons.check_circle_outlined,
              size: 18,
              color: selected ? Pm.primary : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? Pm.primary : Pm.textPrimary)),
            ),
            Text(sublabel,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

/* ─── 공통 헬퍼 ─── */
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
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
  return _commaFmt(int.tryParse(noLeading) ?? 0);
}

// ── 날짜 선택 옵션 타일 (정책 적용일 다이얼로그용)
class _DateOptionTile extends StatelessWidget {
  const _DateOptionTile({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String sublabel;
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
                  const SizedBox(height: 2),
                  Text(sublabel,
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
