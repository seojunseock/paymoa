// lib/screens/subscription_screen.dart
// RevenueCat 제거됨 - 추후 재연동 예정. 현재는 플랜 정의와 "준비 중" UI만 유지.
import 'package:flutter/material.dart';

// ─────────────────────────────────────────
// 구독 기능 플래그
// ─────────────────────────────────────────
/// false 로 설정 시 플랜 한도 강제 미적용
const kSubscriptionEnabled = true;

/// false 로 설정 시 구독 UI 전체 숨김 (결제 연동 전까지 false 유지)
const kSubscriptionVisible = false;

// ─────────────────────────────────────────
// 플랜 정의
// ─────────────────────────────────────────
enum PlanTier { free, classic, pro, business }

class PlanInfo {
  final PlanTier tier;
  final String name;
  final int maxStores;
  final int maxWorkers;
  final int monthlyPrice; // 0 = 무료
  final String badge;

  const PlanInfo({
    required this.tier,
    required this.name,
    required this.maxStores,
    required this.maxWorkers,
    required this.monthlyPrice,
    this.badge = '',
  });

  int annualPrice(double discountRate) =>
      (monthlyPrice * 12 * (1 - discountRate)).round();

  int annualMonthlyEquiv(double discountRate) =>
      (monthlyPrice * (1 - discountRate)).round();
}

const kPlans = [
  PlanInfo(
    tier: PlanTier.free,
    name: '무료',
    maxStores: 1,
    maxWorkers: 5,
    monthlyPrice: 0,
  ),
  PlanInfo(
    tier: PlanTier.classic,
    name: '클래식',
    maxStores: 1,
    maxWorkers: 10,
    monthlyPrice: 4000,
  ),
  PlanInfo(
    tier: PlanTier.pro,
    name: '프로',
    maxStores: 2,
    maxWorkers: 25,
    monthlyPrice: 10000,
    badge: '추천',
  ),
  PlanInfo(
    tier: PlanTier.business,
    name: '비즈니스',
    maxStores: 5,
    maxWorkers: 40,
    monthlyPrice: 19000,
  ),
];

// ─────────────────────────────────────────
// 전체 화면 (준비 중)
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
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded,
                  size: 64, color: Color(0xFF7C3AED)),
              SizedBox(height: 24),
              Text(
                '구독 플랜',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              SizedBox(height: 12),
              Text(
                '준비 중입니다.\n곧 만나보실 수 있어요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 바텀시트 (준비 중)
// ─────────────────────────────────────────
class SubscriptionSheet extends StatelessWidget {
  const SubscriptionSheet({
    super.key,
    this.currentTier = PlanTier.free,
  });

  final PlanTier currentTier;

  /// 바텀시트로 구독 플랜 화면 표시
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
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 48, color: Color(0xFF7C3AED)),
                SizedBox(height: 16),
                Text(
                  '준비 중입니다.\n곧 만나보실 수 있어요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF6B7280),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
