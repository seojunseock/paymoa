// lib/screens/subscription_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../subscription/subscription_service.dart';
import '../services/promo_service.dart';

// ─────────────────────────────────────────
// 구독 기능 플래그
// ─────────────────────────────────────────
/// false 시 플랜 한도 미적용
const kSubscriptionEnabled = true;

/// false 시 구독 UI 전체 숨김
const kSubscriptionVisible = true;

// ─────────────────────────────────────────
// 플랜 정의
// ─────────────────────────────────────────
enum PlanTier { free, basic, pro }

class PlanInfo {
  final PlanTier tier;
  final String name;
  final int maxStores;
  final int maxWorkers;
  /// iOS App Store 가격 (원)
  final int monthlyPriceIos;
  /// Google Play Store 가격 (원)
  final int monthlyPriceAndroid;
  final String badge;
  final bool showAds;

  const PlanInfo({
    required this.tier,
    required this.name,
    required this.maxStores,
    required this.maxWorkers,
    required this.monthlyPriceIos,
    required this.monthlyPriceAndroid,
    this.badge = '',
    this.showAds = false,
  });

  /// 현재 플랫폼에 맞는 가격 반환
  int get monthlyPrice => Platform.isIOS ? monthlyPriceIos : monthlyPriceAndroid;

  String get workersLabel => '$maxWorkers명';
}

const kPlans = [
  PlanInfo(
    tier: PlanTier.free,
    name: '무료',
    maxStores: 1,
    maxWorkers: 8,
    monthlyPriceIos: 0,
    monthlyPriceAndroid: 0,
    showAds: true,
  ),
  PlanInfo(
    tier: PlanTier.basic,
    name: '베이직',
    maxStores: 1,
    maxWorkers: 20,
    monthlyPriceIos: 2500,     // TODO: 애플 실제 가격으로 교체
    monthlyPriceAndroid: 2500, // TODO: 플레이스토어 실제 가격으로 교체
    showAds: false,
  ),
  PlanInfo(
    tier: PlanTier.pro,
    name: '프로',
    maxStores: 5,
    maxWorkers: 100,
    monthlyPriceIos: 9900,     // TODO: 애플 실제 가격으로 교체
    monthlyPriceAndroid: 9900, // TODO: 플레이스토어 실제 가격으로 교체
    showAds: false,
    badge: '추천',
  ),
];

// ─────────────────────────────────────────
// 전체 화면
// ─────────────────────────────────────────
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({
    super.key,
    this.currentTier = PlanTier.free,
  });

  final PlanTier currentTier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF111827)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '구독 플랜',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: _SubscriptionBody(currentTier: currentTier),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 바텀시트
// ─────────────────────────────────────────
class SubscriptionSheet extends StatelessWidget {
  const SubscriptionSheet({
    super.key,
    this.currentTier = PlanTier.free,
  });

  final PlanTier currentTier;

  static Future<void> show(
    BuildContext context, {
    PlanTier currentTier = PlanTier.free,
  }) {
    if (!kSubscriptionVisible) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscriptionSheet(currentTier: currentTier),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F7FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들바
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                const Text(
                  '구독 플랜',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF6B7280)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // 본문 (스크롤 가능)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: _SubscriptionBody(currentTier: currentTier),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// 공통 본문 (화면/시트 공유)
// ─────────────────────────────────────────
class _SubscriptionBody extends StatefulWidget {
  const _SubscriptionBody({required this.currentTier});
  final PlanTier currentTier;

  @override
  State<_SubscriptionBody> createState() => _SubscriptionBodyState();
}

class _SubscriptionBodyState extends State<_SubscriptionBody> {
  bool _loadingBasic = false;
  bool _loadingPro = false;
  String? _errorMsg;

  Future<void> _onSubscribeBasic() async {
    setState(() { _loadingBasic = true; _errorMsg = null; });
    try {
      final success = await SubscriptionService.instance.purchaseBasic();
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('베이직 플랜으로 업그레이드됐어요!')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => _errorMsg = '구독 중 오류가 발생했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loadingBasic = false);
    }
  }

  Future<void> _onSubscribePro() async {
    setState(() { _loadingPro = true; _errorMsg = null; });
    try {
      final success = await SubscriptionService.instance.purchasePro(
        discountProductId: PromoService.instance.discountProductId,
      );
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로 플랜으로 업그레이드됐어요!')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => _errorMsg = '구독 중 오류가 발생했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loadingPro = false);
    }
  }

  Future<void> _onPromoCode() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OwnerPromoDialog(ctrl: ctrl),
    );
    if (!mounted) return;
    if (PromoService.instance.isProGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로 플랜이 적용됐어요!')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _onRestore() async {
    setState(() {
      _loadingPro = true;
      _errorMsg = null;
    });
    try {
      final restored = await SubscriptionService.instance.restorePurchases();
      if (!mounted) return;
      if (restored) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구독이 복원됐어요!')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원할 구독 내역이 없어요.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _errorMsg = '복원 중 오류가 발생했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loadingPro = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.currentTier;
    final isPro = tier == PlanTier.pro;
    final isBasic = tier == PlanTier.basic;
    final isFree = tier == PlanTier.free;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),

        // ── 무료 플랜 카드 ──
        _PlanCard(plan: kPlans[0], isCurrentPlan: isFree),
        const SizedBox(height: 10),

        // ── 베이직 플랜 카드 ──
        _PlanCard(
          plan: kPlans[1],
          isCurrentPlan: isBasic,
          onSubscribe: isFree ? _onSubscribeBasic : null,
          loading: _loadingBasic,
        ),
        const SizedBox(height: 10),

        // ── 프로 플랜 카드 ──
        _PlanCard(
          plan: kPlans[2],
          isCurrentPlan: isPro,
          onSubscribe: !isPro ? _onSubscribePro : null,
          loading: _loadingPro,
          promoDiscountPercent: PromoService.instance.hasDiscount
              ? PromoService.instance.discountPercent?.toDouble()
              : null,
          isUpgrade: isBasic,
        ),
        const SizedBox(height: 16),

        // ── 복원 / 프로모 코드 ──
        if (!isPro)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: (_loadingBasic || _loadingPro) ? null : _onRestore,
                child: const Text('구매 내역 복원하기',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280),
                        decoration: TextDecoration.underline)),
              ),
              if (!Platform.isIOS) ...[
                const Text('·', style: TextStyle(color: Color(0xFF6B7280))),
                TextButton(
                  onPressed: (_loadingBasic || _loadingPro) ? null : _onPromoCode,
                  child: const Text('프로모션 코드',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280),
                          decoration: TextDecoration.underline)),
                ),
              ],
            ],
          ),

        // ── 에러 메시지 ──
        if (_errorMsg != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMsg!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFFEF4444)),
          ),
        ],

        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────
// 플랜 카드
// ─────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrentPlan,
    this.onSubscribe,
    this.loading = false,
    this.promoDiscountPercent,
    this.isUpgrade = false,
  });

  final PlanInfo plan;
  final bool isCurrentPlan;
  final VoidCallback? onSubscribe;
  final bool loading;
  final double? promoDiscountPercent;
  final bool isUpgrade;

  @override
  Widget build(BuildContext context) {
    final borderColor = isCurrentPlan
        ? const Color(0xFF7C3AED)
        : const Color(0xFFE5E7EB);
    final bgColor = isCurrentPlan
        ? const Color(0xFFF5F3FF)
        : Colors.white;
    final nameColor = isCurrentPlan
        ? const Color(0xFF7C3AED)
        : const Color(0xFF111827);

    // 버튼 라벨 계산
    String? btnLabel;
    if (onSubscribe != null) {
      if (plan.tier == PlanTier.basic) {
        btnLabel = '베이직 구독하기  ${_comma(plan.monthlyPrice)}원/월';
      } else {
        final label = isUpgrade ? '프로로 업그레이드' : '프로 구독하기';
        if (promoDiscountPercent != null) {
          final discounted =
              (plan.monthlyPrice * (1 - promoDiscountPercent! / 100)).round();
          btnLabel = '$label  ${_comma(discounted)}원/월';
        } else {
          btnLabel = '$label  ${_comma(plan.monthlyPrice)}원/월';
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: borderColor, width: isCurrentPlan ? 2.0 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 행 ──
          Row(
            children: [
              Text(
                plan.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: nameColor,
                ),
              ),
              if (plan.badge.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    plan.badge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (isCurrentPlan)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '현재 플랜',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 기능 목록 ──
          _FeatureRow(icon: Icons.store_outlined, label: '매장 ${plan.maxStores}개'),
          const SizedBox(height: 6),
          _FeatureRow(icon: Icons.people_outline, label: '알바생 ${plan.workersLabel}'),
          const SizedBox(height: 6),
          _FeatureRow(
            icon: plan.showAds ? Icons.campaign_outlined : Icons.block_outlined,
            label: plan.showAds ? '광고 있음' : '광고 없음',
            color: plan.showAds
                ? const Color(0xFF9CA3AF)
                : const Color(0xFF059669),
          ),
          if (plan.monthlyPrice > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${_comma(plan.monthlyPrice)}원/월',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF7C3AED),
              ),
            ),
          ],
          // ── 구독 버튼 (카드 안) ──
          if (btnLabel != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: loading ? null : onSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        btnLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF6B7280),
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
          ),
        ),
      ],
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

// ── 사장님 프로모션 코드 다이얼로그 ──
class _OwnerPromoDialog extends StatefulWidget {
  const _OwnerPromoDialog({required this.ctrl});
  final TextEditingController ctrl;

  @override
  State<_OwnerPromoDialog> createState() => _OwnerPromoDialogState();
}

class _OwnerPromoDialogState extends State<_OwnerPromoDialog> {
  bool _loading = false;
  String? _msg;
  bool _success = false;

  Future<void> _apply() async {
    final code = widget.ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _loading = true; _msg = null; });

    final result = await PromoService.instance.applyCode(code);
    if (!mounted) return;

    final proPrice = kPlans.last.monthlyPrice;
    setState(() {
      _loading = false;
      switch (result) {
        case PromoResult.success:
          _success = true;
          _msg = '코드가 적용됐어요!';
        case PromoResult.discount:
          _success = true;
          final pct = PromoService.instance.discountPercent ?? 0;
          final discounted = (proPrice * (1 - pct / 100)).round();
          _msg = '$pct% 할인 적용! ${_comma(discounted)}원/월로 구독할 수 있어요.';
        case PromoResult.already:
          _msg = '이미 적용된 코드예요.';
        case PromoResult.invalid:
          _msg = '유효하지 않은 코드예요.';
        case PromoResult.error:
          _msg = '오류가 발생했어요. 다시 시도해주세요.';
      }
    });

    if (_success) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('프로모션 코드',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '코드를 입력해주세요',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF7C3AED), width: 2)),
            ),
            onSubmitted: (_) => _apply(),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!,
                style: TextStyle(
                    fontSize: 13,
                    color: _success
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFEF4444))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소',
              style: TextStyle(color: Color(0xFF6B7280))),
        ),
        TextButton(
          onPressed: _loading ? null : _apply,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF7C3AED)))
              : const Text('적용',
                  style: TextStyle(
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
