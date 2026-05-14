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
import '../subscription_screen.dart';
import '../../subscription/subscription_service.dart';
import '../../ads/ad_service.dart';

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
            .showSnackBar(const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해 주세요.')));
      }
    }
  }

  void _onAddStoreTap(List<Store> currentStores) {
    if (kSubscriptionEnabled && kSubscriptionVisible) {
      final planLimit = SubscriptionService.instance.cached?.plan.maxStores
          ?? kPlans[0].maxStores;
      if (currentStores.length >= planLimit) {
        SubscriptionSheet.show(context,
            currentTier:
                SubscriptionService.instance.cached?.tier ?? PlanTier.free);
        return;
      }
    }
    AppNav.openOwnerStoreCreate(context);
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

    return StreamBuilder<List<Store>>(
      stream: _repo.watchStores(user.uid),
      builder: (ctx, snap) {
        final stores = snap.data ?? const <Store>[];
        final loading = snap.connectionState == ConnectionState.waiting &&
            !snap.hasData;

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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _onAddStoreTap(stores),
            backgroundColor: Pm.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              '매장',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: () {
            if (loading) {
              return const Center(
                child: CircularProgressIndicator(color: Pm.primary),
              );
            }
            if (snap.hasError) {
              return const Center(
                child: Text('데이터를 불러올 수 없어요.\n네트워크 연결을 확인해 주세요.',
                    style: TextStyle(color: Pm.textSecondary)),
              );
            }
            if (stores.isEmpty) {
              return _EmptyView(onAdd: () => _onAddStoreTap(stores));
            }

            // ── 구독 플랜 한도 분기 ──────────────────────
            final subInfo = SubscriptionService.instance.cached;
            final isExpired =
                subInfo?.status == SubscriptionStatus.expired;
            final isGrace =
                subInfo?.status == SubscriptionStatus.gracePeriod;
            // kSubscriptionVisible = true 시 플랜 한도 적용, 유예기간 중은 제한 없음
            final planLimit = (kSubscriptionEnabled && kSubscriptionVisible && !isGrace)
                ? (subInfo?.plan.maxStores ?? 999)
                : 999;
            final normalStores =
                stores.length <= planLimit ? stores : stores.sublist(0, planLimit);
            final lockedStores =
                stores.length > planLimit ? stores.sublist(planLimit) : <Store>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                // 유예기간 배너
                if (kSubscriptionEnabled && isGrace) ...[
                  _SubscriptionBanner(
                    message:
                        '결제에 문제가 생겼어요. 유예기간 ${subInfo!.remainingGraceDays}일 남았어요.',
                    color: const Color(0xFFFEF3C7),
                    iconColor: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 8),
                ],
                // 한도 초과 / 만료 배너
                if (kSubscriptionEnabled && isExpired) ...[
                  _SubscriptionBanner(
                    message: '구독이 만료됐어요. 일부 기능이 제한됩니다.',
                    color: const Color(0xFFFEE2E2),
                    iconColor: const Color(0xFFF43F5E),
                    onUpgrade: () => SubscriptionSheet.show(context),
                  ),
                  const SizedBox(height: 8),
                ] else if (kSubscriptionEnabled && kSubscriptionVisible && lockedStores.isNotEmpty) ...[
                  _SubscriptionBanner(
                    message: '플랜 한도에 도달했어요. 업그레이드하면 더 많은 매장을 관리할 수 있어요.',
                    color: const Color(0xFFF3EEFF),
                    iconColor: const Color(0xFF7C3AED),
                    onUpgrade: () => SubscriptionSheet.show(context),
                  ),
                  const SizedBox(height: 8),
                ],
                // 정상 매장
                ...normalStores.map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _StoreCard(
                        store: s,
                        isLocked: false,
                        onEdit: () =>
                            AppNav.openOwnerStoreEdit(context: context, store: s),
                        onDelete: () => _confirmDelete(s),
                        onTap: () {
                          final tier = SubscriptionService.instance.cached?.tier ?? PlanTier.free;
                          if (tier == PlanTier.free) {
                            AdService.instance.showInterstitial(
                              onAdClosed: () => AppNav.openOwnerStoreDetail(context: context, store: s),
                            );
                          } else {
                            AppNav.openOwnerStoreDetail(context: context, store: s);
                          }
                        },
                      ),
                    )),
                // 잠긴 매장
                if (lockedStores.isNotEmpty) ...[
                  if (normalStores.isNotEmpty) const SizedBox(height: 4),
                  ...lockedStores.map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _StoreCard(
                          store: s,
                          isLocked: true,
                          onEdit: () {},
                          onDelete: () => _confirmDelete(s),
                          onTap: () => SubscriptionSheet.show(context),
                        ),
                      )),
                ],
              ],
            );
          }(),
        );
      },
    );
  }
}

/* ─── 구독 배너 ──────────────────────────────── */
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({
    required this.message,
    required this.color,
    required this.iconColor,
    this.onUpgrade,
  });

  final String message;
  final Color color;
  final Color iconColor;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
          if (onUpgrade != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onUpgrade,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '플랜 업그레이드',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
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
    this.isLocked = false,
  });

  final Store store;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final bool isLocked;

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

    return Opacity(
      opacity: isLocked ? 0.4 : 1.0,
      child: Stack(
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
                        if (isLocked) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.lock_rounded,
                              size: 16, color: Color(0xFF9CA3AF)),
                        ] else if ((store.storeCode ?? '').trim().isNotEmpty) ...[
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
                    if (!isLocked)
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
      ),
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
