// lib/screens/owner/owner_store_list_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../common/app_words.dart';
import '../../common/paymoa_design.dart';
import '../../data/firebase_service.dart';
import '../../models/store.dart';
import '../../navigation/app_nav.dart';
import '../../policies/policies.dart' as pol;
import '../../policies/policy_mapper.dart' as pm;
import '../../payroll/payroll.dart';
import '../../payroll/payroll_policy_mapper.dart' as ppm;

/* ─── helpers ─────────────────────────────────── */
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

String _labelTax(pol.TaxConfig t) {
  if (t == pol.TaxConfig.biz33) return '사업소득세 3.3%';
  if (t == pol.TaxConfig.day66) return '일용직 6.6%';
  if (t is pol.TaxConfigCustomPercent) return '커스텀 ${t.percent}%';
  return AppWords.none;
}

String _labelIns(pol.InsuranceConfig i) {
  if (i is pol.InsuranceEmploymentOnly) return '고용보험';
  if (i is pol.InsuranceFour) return '4대보험';
  return AppWords.none;
}

String _labelSur(pol.SurchargePolicy? s) {
  if (s == null) return AppWords.none;
  final parts = <String>[];
  if (s.weeklyHolidayEnabled) parts.add('주휴수당');
  if (s.overtimeEnabled) parts.add('연장');
  if (s.nightEnabled) parts.add('야간');
  if (s.holidayEnabled) parts.add('휴일');
  return parts.isEmpty ? AppWords.none : parts.join(' · ');
}

String _labelPayroll(PayrollPolicy? p) {
  if (p == null) return AppWords.none;
  final type = p.cycle == PayCycleType.daily
      ? '일급'
      : p.cycle == PayCycleType.monthly
          ? ((p.monthlyStartDay ?? 1) == 1
              ? '한 달(1일~말일)'
              : '매달 ${p.monthlyStartDay}일 시작')
          : '급여 방식';
  final pay = () {
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
  return '$type · $pay';
}

/* ══════════════════════════════════════════════
   매장 리스트
   ══════════════════════════════════════════════ */

class OwnerStoreListScreen extends StatefulWidget {
  const OwnerStoreListScreen({super.key});

  @override
  State<OwnerStoreListScreen> createState() => _OwnerStoreListScreenState();
}

class _OwnerStoreListScreenState extends State<OwnerStoreListScreen> {
  final _repo = FirebaseService();

  Future<void> _confirmDelete(Store store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('매장 삭제'),
        content: Text(
          '"${store.name}"을 삭제하면\n매장 데이터와 초대코드가 모두 삭제돼요.\n계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppWords.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppWords.delete,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _repo.deleteStore(
          uid: user.uid, storeId: store.id, storeCode: store.storeCode);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('매장이 삭제됐어요.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F7FF),
        body: Center(child: Text('로그인이 필요해요.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          '페이모아',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: Pm.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AppNav.openOwnerStoreCreate(context),
        backgroundColor: Pm.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<Store>>(
        stream: _repo.watchStores(user.uid),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Pm.primary),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text('오류: ${snap.error}',
                  style: const TextStyle(color: Pm.textSecondary)),
            );
          }

          final stores = snap.data ?? const <Store>[];
          if (stores.isEmpty) {
            return _EmptyView(
                onAdd: () => AppNav.openOwnerStoreCreate(context));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: stores.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _StoreCard(
                store: stores[i],
                onEdit: () => AppNav.openOwnerStoreEdit(
                    context: context, store: stores[i]),
                onDelete: () => _confirmDelete(stores[i]),
                onTap: () => AppNav.openOwnerStoreDetail(
                    context: context, store: stores[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/* ══════════════════════════════════════════════
   매장 카드 — 항상 펼쳐진 상태
   ══════════════════════════════════════════════ */

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  final Store store;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = pmColor(store.colorHex);

    // 정책 파싱
    final policy =
        (store.policy ?? const <String, dynamic>{}).cast<String, dynamic>();
    final tax = pm.taxConfigFromPolicy(policy);
    final ins = pm.insuranceConfigFromPolicy(policy);
    final sur = pm.surchargePolicyFromPolicy(policy);
    final rawPR = policy['payrollPolicy'];
    final PayrollPolicy? payroll = rawPR is Map
        ? ppm.payrollPolicyFromMap(rawPR.cast<String, dynamic>())
        : null;

    final rows = <Widget>[];
    if (store.defaultHourlyWage != null)
      rows.add(pmKv('시급', '${_comma(store.defaultHourlyWage!)}원'));

    if (store.taxEnabled) rows.add(pmKv(AppWords.tax, _labelTax(tax)));
    if (store.insuranceEnabled)
      rows.add(pmKv(AppWords.insurance, _labelIns(ins)));
    if (store.surchargeEnabled)
      rows.add(pmKv(AppWords.surcharge, _labelSur(sur)));
    if (payroll != null)
      rows.add(pmKv(AppWords.payroll, _labelPayroll(payroll)));

    return Stack(
      children: [
        // ── 카드 본체 ──────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Pm.card,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(16),
            ),
            border: Border.all(color: Pm.border, width: 1),
            boxShadow: Pm.cardShadow,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(16)),
              splashColor: accent.withOpacity(0.04),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 매장명 + 초대코드
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            store.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Pm.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ((store.storeCode ?? '').trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Pm.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              store.storeCode!.trim(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Pm.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '내 매장',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),

                    // ── 정책 행들
                    if (rows.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: accent.withOpacity(0.15)),
                      const SizedBox(height: 10),
                      ...rows,
                    ],

                    // ── 버튼
                    const SizedBox(height: 10),
                    Divider(height: 1, color: Pm.divider),
                    const SizedBox(height: 2),
                    pmActionRow(onDelete: onDelete, onEdit: onEdit),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── 컬러 바 ────────────────────────────
        Positioned(
          left: 0,
          top: 7,
          bottom: 7,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ─── 빈 화면 ────────────────────────────────── */
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Pm.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_outlined,
                  size: 56, color: Pm.primary),
            ),
            const SizedBox(height: 24),
            const Text(
              '아직 등록된 매장이 없어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Pm.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '오른쪽 아래 + 버튼을 눌러\n첫 매장을 추가해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Pm.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
