// lib/screens/owner/owner_worker_form_screen.dart
// ✅ store form과 완전 동일한 디자인 패턴으로 통일
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../common/paymoa_design.dart';
import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../models/store_schedule.dart';
import '../../common/ui/money_text_controller.dart';
import '../../data/firebase_service.dart';
import '../../policies/policies.dart' as pol;
import '../../policies/policy_sheet.dart';
import '../../policies/policy_mapper.dart' as pm;
import '../../common/common_pickers.dart' as cp;
import '../../common/help_dialog.dart';

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

/* ─── _SettingRow (store form _OwnerSettingRow 동일) ─── */
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.helpTitle,
    this.helpBody,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  final String? helpTitle;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
              if (helpTitle != null) ...[
                const SizedBox(width: 6),
                helpIcon(context, title: helpTitle!, body: helpBody!),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFFD1D5DB)),
            ],
          ),
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

  final _nameFocus = FocusNode();
  final _wageFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _formattingWage = false;
  bool _inheritFromStore = true;

  int? _initialWage; // ✅ 저장 전 기존 시급
  pol.SurchargePolicy? _initialSurcharge; // ✅ 저장 전 기존 정책 (변경 감지용)
  pol.TaxConfig? _initialTax;
  pol.InsuranceConfig? _initialIns;

  pol.TaxConfig _tax = pol.TaxConfig.none;
  pol.InsuranceConfig _ins = const pol.InsuranceNone();
  pol.SurchargePolicy _surcharge = const pol.SurchargePolicy();
  Map<String, dynamic> _rawPolicyOverride = {};

  bool _initialInheritFromStore = true;
  DateTime? _modeEffectiveFrom;

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
    _nameFocus.dispose();
    _wageFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _bootstrap() async {
    try {
      final snap = await _workerDoc.get();
      final m = snap.data() ?? <String, dynamic>{};

      _nameCtrl.text =
          (m['displayName'] as String?) ?? (widget.worker.displayName ?? '');

      _inheritFromStore = (m['inheritFromStore'] as bool?) ?? true;
      _initialInheritFromStore = _inheritFromStore;

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
      _initialTax = _tax;
      _initialIns = _ins;
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '데이터를 불러오지 못했어요.\n네트워크 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  /// 세금·보험만 바뀌었는지
  bool _taxInsChanged() {
    if (_initialTax != _tax) return true;
    if (_initialIns.runtimeType != _ins.runtimeType) return true;
    return false;
  }

  /// 가산정책(주휴·연장·휴일·야간)만 바뀌었는지
  bool _surchargeChanged() {
    final before = _initialSurcharge;
    final after = _surcharge;
    if ((before?.weeklyHolidayEnabled ?? false) != after.weeklyHolidayEnabled) {
      return true;
    }
    if ((before?.overtimeEnabled ?? false) != after.overtimeEnabled) {
      return true;
    }
    if ((before?.overtimePercent ?? 0) != after.overtimePercent) {
      return true;
    }
    if ((before?.overtimeRule ?? pol.OvertimeRule.dailyOver8) !=
        after.overtimeRule) {
      return true;
    }
    if ((before?.holidayEnabled ?? false) != after.holidayEnabled) {
      return true;
    }
    if ((before?.holidayPercent ?? 0) != after.holidayPercent) {
      return true;
    }
    if ((before?.nightEnabled ?? false) != after.nightEnabled) {
      return true;
    }
    if ((before?.nightPercent ?? 0) != after.nightPercent) {
      return true;
    }
    return false;
  }

  Future<DateTime?> _showMonthChoiceDialog({String title = '언제부터 적용할까요?'}) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);

    Widget tile(BuildContext ctx, String label, String sub, DateTime val) =>
        InkWell(
          onTap: () => Navigator.pop(ctx, val),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9E4FF)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827))),
                      const SizedBox(height: 2),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFD1D5DB)),
              ],
            ),
          ),
        );

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(ctx, '이번 달부터', '${thisMonth.month}월 1일부터 적용', thisMonth),
            const SizedBox(height: 8),
            tile(ctx, '다음 달부터', '${nextMonth.month}월 1일부터 적용', nextMonth),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    _dismissKeyboard();

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showErrorDialog(context, '이름을 적어주세요.');
      return;
    }

    final wage = _wageCtrl.valueInt;
    if (!_inheritFromStore && wage <= 0) {
      showErrorDialog(context, '개인 설정 시 시급을 입력해 주세요.');
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime effectiveFrom = today;

    final bool modeChanged = _inheritFromStore != _initialInheritFromStore;
    final bool wageWillChange =
        !_inheritFromStore && _initialWage != null && wage != _initialWage;
    final bool taxInsWillChange = !_inheritFromStore && _taxInsChanged();
    final bool surchargeWillChange = !_inheritFromStore && _surchargeChanged();
    final bool policyWillChange = taxInsWillChange || surchargeWillChange;

    DateTime? wageSurchargeFrom; // 시급·가산정책: 달력으로 날짜 선택
    DateTime? taxInsFrom;        // 세금·보험: 이번달/다음달 선택

    if (modeChanged) {
      // 모드 변경: 토글 누를 때 이미 월 단위로 선택됨
      DateTime? picked;
      if (_modeEffectiveFrom != null) {
        picked = _modeEffectiveFrom;
      } else {
        picked = await _showMonthChoiceDialog(title: '언제부터 적용할까요?');
        if (!mounted || picked == null) return;
      }
      effectiveFrom = picked!;
      wageSurchargeFrom = effectiveFrom;
      taxInsFrom = effectiveFrom;
    } else {
      if (wageWillChange || surchargeWillChange) {
        final picked = await cp.showSingleDatePickerDialog(
          context,
          initialDate: today,
          firstDay: DateTime(2020),
          lastDay: today.add(const Duration(days: 365)),
          title: '시급·가산정책 적용일',
        );
        if (!mounted || picked == null) return;
        wageSurchargeFrom = DateTime(picked.year, picked.month, picked.day);
      }
      if (taxInsWillChange) {
        final picked = await _showMonthChoiceDialog(title: '세금·보험 적용 시작');
        if (!mounted || picked == null) return;
        taxInsFrom = picked;
      }
      effectiveFrom = wageSurchargeFrom ?? taxInsFrom ?? today;
    }

    if (modeChanged || wageWillChange || policyWillChange) {
      // 확인 다이얼로그
      final lines = <String>[];
      if (modeChanged) {
        final dateLabel = '${effectiveFrom.month}월 ${effectiveFrom.day}일';
        lines.add(_inheritFromStore
            ? '· $dateLabel부터 매장 설정으로 변경됩니다.'
            : '· $dateLabel부터 개인 설정으로 변경됩니다.');
      }
      if (wageWillChange) {
        final d = wageSurchargeFrom!;
        lines.add('· ${d.month}월 ${d.day}일부터 시급이 적용됩니다.');
      }
      if (surchargeWillChange) {
        final d = wageSurchargeFrom!;
        lines.add('· ${d.month}월 ${d.day}일부터 가산정책(주휴·연장 등)이 적용됩니다.');
      }
      if (taxInsWillChange) {
        final d = taxInsFrom!;
        lines.add('· ${d.month}월 ${d.day}일부터 세금·보험이 적용됩니다.');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            '적용 시작일 안내',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: Text(
            lines.join('\n\n'),
            style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                '취소',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '확인',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) return;
    }

    setState(() => _saving = true);

    try {
      final bool wageChanged =
          !_inheritFromStore && _initialWage != null && wage != _initialWage;

      // 오늘 이전 스케줄은 기존 시급으로 고정 (소급 방지)
      if (wageChanged && widget.workerSchedules.isNotEmpty) {
        await _repo.bulkUpdateStoreScheduleWage(
          ownerUid: _ownerUid,
          storeId: _storeId,
          workerUid: _workerUid,
          newWage: _initialWage!,
          schedules: widget.workerSchedules,
          todayOnly: false,
          fromDate: DateTime(1970),
          untilDate: wageSurchargeFrom ?? effectiveFrom,
        );
      }

      // 가산정책: 오늘 즉시 적용 (켜면 바로 카운트, 끄면 바로 제외)
      // 세금·보험: taxInsEffective (다음 달 1일 또는 오늘이 1일이면 오늘)
      // 둘 다 바뀌면 각자 날짜로 별도 history entry 생성
      final DateTime? policyEffectiveFrom;
      final DateTime? surchargeEffectiveFrom;
      if (taxInsWillChange && surchargeWillChange) {
        policyEffectiveFrom = taxInsFrom;
        surchargeEffectiveFrom = wageSurchargeFrom;
      } else if (taxInsWillChange) {
        policyEffectiveFrom = taxInsFrom;
        surchargeEffectiveFrom = null;
      } else if (surchargeWillChange) {
        policyEffectiveFrom = wageSurchargeFrom;
        surchargeEffectiveFrom = null;
      } else {
        policyEffectiveFrom = null;
        surchargeEffectiveFrom = null;
      }

      await _repo.saveWorkerSettings(
        ownerUid: _ownerUid,
        storeId: _storeId,
        workerUid: _workerUid,
        displayName: name,
        inheritFromStore: _inheritFromStore,
        hourlyWage: _inheritFromStore ? null : wage,
        previousHourlyWage:
            (!_inheritFromStore && _initialWage != null && wage != _initialWage)
                ? _initialWage
                : null,
        policyOverride: _inheritFromStore ? null : _buildPolicyOverride(),
        effectiveFrom: effectiveFrom,
        policyEffectiveFrom: policyEffectiveFrom,
        surchargeEffectiveFrom: surchargeEffectiveFrom,
        previousPolicyOverride: _inheritFromStore ? null : _rawPolicyOverride,
      );

      // 오늘 이후 스케줄에 새 시급 일괄 적용
      if (!_inheritFromStore && wage > 0 && widget.workerSchedules.isNotEmpty) {
        await _repo.bulkUpdateStoreScheduleWage(
          ownerUid: _ownerUid,
          storeId: _storeId,
          workerUid: _workerUid,
          newWage: wage,
          schedules: widget.workerSchedules,
          todayOnly: false,
          fromDate: wageSurchargeFrom ?? effectiveFrom,
        );
      }

      if (!mounted) return;
      _snack(modeChanged || wageWillChange || policyWillChange
          ? '${effectiveFrom.month}월 ${effectiveFrom.day}일부터 적용돼요.'
          : '저장됐어요.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '저장에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _endWorker() async {
    _dismissKeyboard();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알바생 내보내기'),
        content: const Text('이 알바생을 내보낼까요?\n근무 기록은 모두 보존돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '취소',
              style: TextStyle(
                color: Pm.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '내보내기',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFF43F5E),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
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
      showErrorDialog(context, '내보내기에 실패했어요.\n잠시 후 다시 시도해 주세요.');
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
          widget.worker.displayName?.isNotEmpty == true
              ? widget.worker.displayName!
              : '알바생 설정',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: _textPrimary,
          ),
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
                color: _saving ? _textTertiary : Pm.primary,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissKeyboard,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  // ① 알바생 이름
                  _FormCard(
                    label: '알바생',
                    child: TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) {
                        if (_inheritFromStore) {
                          _dismissKeyboard();
                        } else {
                          FocusScope.of(context).requestFocus(_wageFocus);
                        }
                      },
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: '이름',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFD1D5DB),
                        ),
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
                            color: Pm.primary.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _inheritFromStore
                                ? Icons.store_outlined
                                : Icons.person_outlined,
                            color: Pm.primary,
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
                                  color: _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _inheritFromStore
                                    ? '매장 기본 시급 · 세금 적용'
                                    : '이 알바생만 따로 설정',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _inheritFromStore,
                          activeColor: Pm.primary,
                          onChanged: (v) async {
                            _dismissKeyboard();
                            final picked = await _showMonthChoiceDialog(
                              title: v ? '매장 설정으로 변경' : '개인 설정으로 변경',
                            );
                            if (!mounted || picked == null) return;
                            setState(() {
                              _inheritFromStore = v;
                              _modeEffectiveFrom = picked;
                              if (v) {
                                // 매장 모드로 전환: 개인 설정 초기화
                                _tax = pol.TaxConfig.none;
                                _ins = const pol.InsuranceNone();
                                _surcharge = const pol.SurchargePolicy();
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
                            focusNode: _wageFocus,
                            enabled: !_inheritFromStore,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _dismissKeyboard(),
                            inputFormatters: [
                              MoneyTextController.digitsOnlyFormatter,
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
                                color: Color(0xFFE5E7EB),
                              ),
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
                                : const Color(0xFF374151),
                          ),
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
                          onTap: _inheritFromStore ? null : _openPolicy,
                          enabled: true,
                          helpTitle: '세금이란?',
                          helpBody: '급여를 받을 때 국가에 내는 소득세예요.\n\n'
                              '• 없음 — 세금 없이 급여 전액을 받아요.\n\n'
                              '• 3.3% — 프리랜서·강사처럼 용역 계약으로 일할 때 써요. 급여의 3.3%를 세금으로 내요.\n\n'
                              '• 일용직 (6.6%) — 하루 단위 단기 알바에 써요. 하루 일당에서 15만 원을 먼저 빼고, 남은 금액의 2.97%만 세금으로 내요.\n'
                              '  예) 일당 20만 원 → 5만 원 × 2.97% ≈ 1,485원\n\n'
                              '• 직접 입력 — 세율을 직접 정할 수 있어요.',
                        ),
                        const SizedBox(height: 2),
                        _SettingRow(
                          icon: Icons.health_and_safety_outlined,
                          label: '보험',
                          value: _insLabel(_ins),
                          onTap: _inheritFromStore ? null : _openPolicy,
                          enabled: true,
                          helpTitle: '4대보험이란?',
                          helpBody: '국가에서 운영하는 사회보험이에요. 일부 금액을 급여에서 공제해요.\n\n'
                              '• 없음 — 보험료를 공제하지 않아요.\n\n'
                              '• 고용보험만 (0.9%) — 급여의 0.9%를 공제해요. 나중에 직장을 잃으면 실업급여를 받을 수 있어요.\n\n'
                              '• 4대보험 전체 (~9.4%) — 국민연금 4.5% + 건강보험 3.545% + 고용보험 0.9% + 장기요양 0.45% = 약 9.4%를 공제해요.\n\n'
                              '※ 2026년 근로자 부담분 기준이에요.',
                        ),
                        const SizedBox(height: 2),
                        _SettingRow(
                          icon: Icons.nightlight_outlined,
                          label: '야간 · 연장 · 휴일',
                          value: _surchargeLabel(_surcharge),
                          onTap: _inheritFromStore ? null : _openPolicy,
                          enabled: true,
                          helpTitle: '추가 수당이란?',
                          helpBody: '기본 시급 외에 법이나 약속으로 추가로 받는 돈이에요.\n\n'
                              '아래 각 항목의 ? 버튼을 누르면 계산 방법을 자세히 볼 수 있어요.',
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFFF0F0F5)),
                        const SizedBox(height: 8),
                        _WorkerToggleRow(
                          icon: Icons.calendar_today_rounded,
                          label: '주휴수당',
                          desc: '주 15시간 이상 근무 시 1일치 급여 추가',
                          value: _inheritFromStore
                              ? widget.store.surchargePolicy.weeklyHolidayEnabled
                              : _surcharge.weeklyHolidayEnabled,
                          onChanged: (v) {
                            if (_inheritFromStore) {
                              _snack('개인 설정을 켜면 변경할 수 있어요.');
                              return;
                            }
                            setState(() {
                              _surcharge =
                                  _surcharge.copyWith(weeklyHolidayEnabled: v);
                            });
                          },
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
                        _WorkerToggleRow(
                          icon: Icons.access_time_rounded,
                          label: '주 40시간 초과 연장수당',
                          desc: '한 주 40시간 넘으면 초과분 50% 추가',
                          value: _inheritFromStore
                              ? (widget.store.surchargePolicy.overtimeEnabled &&
                                  widget.store.surchargePolicy.overtimeRule ==
                                      pol.OvertimeRule.weeklyOver40)
                              : (_surcharge.overtimeEnabled &&
                                  _surcharge.overtimeRule ==
                                      pol.OvertimeRule.weeklyOver40),
                          onChanged: (v) {
                            if (_inheritFromStore) {
                              _snack('개인 설정을 켜면 변경할 수 있어요.');
                              return;
                            }
                            setState(() {
                              _surcharge = _surcharge.copyWith(
                                overtimeEnabled: v,
                                overtimeRule: v
                                    ? pol.OvertimeRule.weeklyOver40
                                    : _surcharge.overtimeRule,
                              );
                            });
                          },
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
                          borderRadius: BorderRadius.circular(Pm.radiusBtn),
                        ),
                      ),
                      child: Text(
                        _saving ? '저장하는 중…' : '저장',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // ⑦ 알바생 내보내기 (하단 파괴적 액션)
                  if (!_loading) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: _endWorker,
                        icon: const Icon(
                          Icons.logout_outlined,
                          size: 18,
                          color: Color(0xFFF43F5E),
                        ),
                        label: const Text(
                          '알바생 내보내기',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF43F5E),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFF43F5E),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  // ── 라벨
  String _taxLabel(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return '사업소득세 3.3%';
    if (t == pol.TaxConfig.day66) return '일용소득세 6.6%';
    if (t is pol.TaxConfigCustomPercent) {
      return '${t.percent.toStringAsFixed(1)}%';
    }
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
      'weeklyHolidayUseFixedMinutes': _surcharge.weeklyHolidayUseFixedMinutes,
      'weeklyHolidayFixedMinutes': _surcharge.weeklyHolidayFixedMinutes,
      'weeklyHolidayWeekday': _surcharge.weeklyHolidayWeekday,
      'overtimeEnabled': _surcharge.overtimeEnabled,
      'overtimePercent': _surcharge.overtimePercent,
      'overtimeRule': _surcharge.overtimeRule == pol.OvertimeRule.weeklyOver40
          ? 'weeklyOver40'
          : 'dailyOver8',
      'holidayEnabled': _surcharge.holidayEnabled,
      'holidayPercent': _surcharge.holidayPercent,
      'holidayUseKoreanLawTier': _surcharge.holidayUseKoreanLawTier,
      'nightEnabled': _surcharge.nightEnabled,
      'nightPercent': _surcharge.nightPercent,
      'extraHolidayYmds': _surcharge.extraHolidayYmds.toList(),
    };
    return out;
  }

  dynamic _taxToValue(pol.TaxConfig t) {
    if (t == pol.TaxConfig.biz33) return 'biz33';
    if (t == pol.TaxConfig.day66) return 'day66';
    if (t is pol.TaxConfigCustomPercent) {
      return {'kind': 'customPercent', 'percent': t.percent};
    }
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
      if (cfg is pol.TaxConfigCustomPercent) {
        customPct = max(0.0, cfg.percent);
      }
      return (enabled, cfg, customPct);
    }

    cfg = pm.taxConfigFromAny(raw);
    enabled = cfg != pol.TaxConfig.none;
    if (cfg is pol.TaxConfigCustomPercent) {
      customPct = max(0.0, cfg.percent);
    }
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
      weeklyHolidayUseFixedMinutes: m['weeklyHolidayUseFixedMinutes'] == true,
      weeklyHolidayFixedMinutes:
          (_toInt(m['weeklyHolidayFixedMinutes']) ?? 0).clamp(0, 24 * 60),
      weeklyHolidayWeekday:
          (_toInt(m['weeklyHolidayWeekday']) ?? DateTime.sunday)
              .clamp(DateTime.monday, DateTime.sunday),
      holidayUseKoreanLawTier: m['holidayUseKoreanLawTier'] == true,
      extraHolidayYmds: ((m['extraHolidayYmds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
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

class _WorkerToggleRow extends StatelessWidget {
  const _WorkerToggleRow({
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
    this.helpTitle,
    this.helpBody,
  });

  final IconData icon;
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? helpTitle;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value ? Pm.primary.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: value ? Pm.primary : const Color(0xFF9CA3AF)),
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
                    color: value ? Pm.primary : const Color(0xFF374151),
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: value
                        ? Pm.primary.withOpacity(0.7)
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
            activeColor: Pm.primary,
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
  return _commaFmt(int.tryParse(noLeading) ?? 0);
}
