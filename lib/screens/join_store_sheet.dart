// lib/screens/join_store_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../common/app_words.dart';
import '../models/store.dart';
import '../models/alba_form_models.dart';
import '../policies/policies.dart' as pol;
import 'subscription_screen.dart';
import '../subscription/subscription_service.dart';

class JoinStoreSheetResult {
  final String code;
  final Store store;
  final AlbaFormInitial initial;

  const JoinStoreSheetResult({
    required this.code,
    required this.store,
    required this.initial,
  });
}

class JoinStoreSheet extends StatefulWidget {
  const JoinStoreSheet({super.key});

  @override
  State<JoinStoreSheet> createState() => _JoinStoreSheetState();
}

class _JoinStoreSheetState extends State<JoinStoreSheet> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // 시트 열리면 바로 입력 가능하게
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_codeFocus);
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String _normalizeCode(String s) => s.trim().replaceAll(' ', '');

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() => _loading = v);
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _errorText = msg);
  }

  Future<void> _next() async {
    if (_loading) return;

    final code = _normalizeCode(_codeCtrl.text);

    if (code.isEmpty) {
      _setError('코드를 입력해 주세요.');
      FocusScope.of(context).requestFocus(_codeFocus);
      return;
    }

    FocusScope.of(context).unfocus();

    _setLoading(true);
    _setError(null);

    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('storeJoinCodes').doc(code).get();

      if (!snap.exists) {
        _setError('코드가 맞는지 확인해 주세요.');
        _setLoading(false);
        return;
      }

      final m = (snap.data() ?? <String, dynamic>{});

      final ownerUid = (m['ownerUid'] as String?)?.trim() ?? '';
      final storeId = (m['storeId'] as String?)?.trim() ?? '';

      if (ownerUid.isEmpty || storeId.isEmpty) {
        _setError('코드 정보가 올바르지 않아요.');
        _setLoading(false);
        return;
      }

      final storeName = (m['storeName'] as String?)?.trim();
      final name =
          (storeName != null && storeName.isNotEmpty) ? storeName : '매장';

      // ── 정원 초과 체크 ──────────────────────────────────────────
      if (kSubscriptionEnabled) {
        final workersSnap = await db
            .collection('users')
            .doc(ownerUid)
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .get();

        final activeCount = workersSnap.docs.where((d) {
          final status = d.data()['status'] as String? ?? '';
          return status != 'ended' && status != 'deleted';
        }).length;

        final ownerTier = await SubscriptionService.fetchTierForUid(ownerUid);
        final planLimit = kPlans
            .firstWhere((p) => p.tier == ownerTier, orElse: () => kPlans.first)
            .maxWorkers;

        if (activeCount >= planLimit) {
          // 사장님에게 정원 초과 알림 기록
          await db
              .collection('users')
              .doc(ownerUid)
              .collection('notifications')
              .add({
            'type': 'capacityBlocked',
            'storeId': storeId,
            'storeName': name,
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
          });

          _setError('이 매장의 정원이 꽉 찼어요.\n사장님께 문의해 주세요.');
          _setLoading(false);
          return;
        }
      }
      // ────────────────────────────────────────────────────────────

      final colorHex = (m['colorHex'] as String?) ?? '#3B82F6';

      final hourlyWage =
          _toInt(m['defaultHourlyWage']) ?? _toInt(m['hourlyWage']) ?? 0;

      final payDay = (_toInt(m['payDay']) ?? 25).clamp(1, 31);

      final policy = (m['policy'] as Map?)?.cast<String, dynamic>();

      final store = Store(
        id: storeId,
        ownerUid: ownerUid,
        name: name,
        colorHex: colorHex,
        defaultHourlyWage: hourlyWage,
        payDay: payDay,
        storeCode: code,
        policy: policy,
        createdAt: null,
        updatedAt: null,
      );

      // ✅ store.payrollPolicy는 Store 내부에서 payDay 등을 기반으로 fallback 처리한다고 가정
      final storeDefaults = AlbaStoreDefaultsSnapshot(
        hourlyWage: hourlyWage,
        tax: pol.TaxConfig.none,
        insurance: const pol.InsuranceNone(),
        surcharge: null,
        payrollPolicy: store.payrollPolicy,
        payDay: payDay,
      );

      final initial = AlbaFormInitial(
        storeId: storeId,
        storeName: name,
        hourlyWage: hourlyWage,
        tax: pol.TaxConfig.none,
        insurance: const pol.InsuranceNone(),
        surcharge: null,
        payrollPolicy: storeDefaults.payrollPolicy,
        startHour24: 9,
        startMinute: 0,
        endHour24: 18,
        endMinute: 0,
        breakMinutes: 0,
        selectedDates: {},
        colorHex: colorHex,
        payDay: payDay,
        inheritFromStore: true,
        storeDefaults: storeDefaults,
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        JoinStoreSheetResult(code: code, store: store, initial: initial),
      );
    } catch (e) {
      _setError('매장 코드를 확인하거나 잠시 후 다시 시도해 주세요.');
    } finally {
      _setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeNow = _normalizeCode(_codeCtrl.text);

    return SafeArea(
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppWords.joinByCode,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: AppWords.close,
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '사장님이 준 초대 코드를 입력하면 매장과 자동으로 연결돼요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 입력 카드
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.key_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '초대 코드',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (codeNow.isNotEmpty)
                          Text(
                            codeNow,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeCtrl,
                      focusNode: _codeFocus,
                      enabled: !_loading,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _next(),
                      onChanged: (_) {
                        if (_errorText != null)
                          setState(() => _errorText = null);
                        // 입력 중 대문자 유지(커서 튐 최소화)
                        final n = _normalizeCode(_codeCtrl.text);
                        if (_codeCtrl.text != n) {
                          _codeCtrl.value = TextEditingValue(
                            text: n,
                            selection:
                                TextSelection.collapsed(offset: n.length),
                          );
                        }
                      },
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        hintText: '예) MJ983N7A',
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: theme.colorScheme.primary, width: 1.4),
                        ),
                        prefixIcon:
                            const Icon(Icons.confirmation_number_outlined),
                        errorText: null, // 에러는 아래에서 커스텀
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      _InlineError(text: _errorText!),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _loading ? null : _next,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppWords.next),
                ),
              ),

              const SizedBox(height: 10),
              Text(
                '코드는 대소문자를 구분해요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
