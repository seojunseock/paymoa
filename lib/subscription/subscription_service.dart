// lib/subscription/subscription_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/subscription_screen.dart';
import '../services/promo_service.dart';

// ─────────────────────────────────────────
// RevenueCat API 키
// ─────────────────────────────────────────
const _rcAndroidKey = 'goog_ALUYwdkPcoDpZBDsoamZJcCKwpQ';
// ✅ TODO: RevenueCat 대시보드 → iOS 앱 → API Key 복사 후 아래에 입력
// 키 입력 후 subscription_screen.dart의 kSubscriptionVisible = true 로 변경
const _rcIosKey     = 'appa1fc3a5715';

/// RevenueCat Entitlement ID (RevenueCat 대시보드에서 설정한 이름과 동일해야 함)
const _proEntitlement   = 'pro';
const _basicEntitlement = 'basic';

// ─────────────────────────────────────────
// 구독 상태
// ─────────────────────────────────────────
enum SubscriptionStatus {
  active,       // 정상 구독 중
  gracePeriod,  // 결제 문제 감지, 유예기간 중
  expired,      // 유예기간 종료 → 무료로 다운그레이드
  free,         // 구독 없음
}

// ─────────────────────────────────────────
// 구독 정보 모델
// ─────────────────────────────────────────
class SubscriptionInfo {
  final SubscriptionStatus status;
  final PlanTier tier;
  final DateTime? gracePeriodEndsAt;
  final bool hasBillingIssue;

  const SubscriptionInfo({
    required this.status,
    required this.tier,
    this.gracePeriodEndsAt,
    this.hasBillingIssue = false,
  });

  PlanInfo get plan =>
      kPlans.firstWhere((p) => p.tier == tier, orElse: () => kPlans.first);

  bool get isReadOnlyMode => status == SubscriptionStatus.expired;

  int get remainingGraceDays {
    if (gracePeriodEndsAt == null) return 0;
    return gracePeriodEndsAt!.difference(DateTime.now()).inDays.clamp(0, 3);
  }
}

// ─────────────────────────────────────────
// 서비스 (싱글톤)
// ─────────────────────────────────────────
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  SubscriptionInfo? _cached;
  bool _initialized = false;

  /// 구독 tier 변경 시 UI에 즉시 반영
  final tierNotifier = ValueNotifier<PlanTier>(PlanTier.free);

  SubscriptionInfo? get cached => _cached;
  bool get shouldShowBillingWarning =>
      _cached?.status == SubscriptionStatus.gracePeriod;

  // ── 초기화 (앱 시작 / 로그인 시 1회) ──
  Future<void> init(String uid) async {
    if (!kSubscriptionEnabled) {
      _cached = const SubscriptionInfo(
        status: SubscriptionStatus.active,
        tier: PlanTier.free,
      );
      return;
    }
    if (_initialized) return;
    _initialized = true;

    // 프로모 코드로 pro 지급된 경우
    if (PromoService.instance.isProGranted) {
      _cached = const SubscriptionInfo(
        status: SubscriptionStatus.active,
        tier: PlanTier.pro,
      );
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.error);
      final config = PurchasesConfiguration(
        Platform.isIOS ? _rcIosKey : _rcAndroidKey,
      )..appUserID = uid;
      await Purchases.configure(config);
      await _syncFromRevenueCat();
    } catch (_) {
      _cached ??= const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }
  }

  // ── RevenueCat에서 구독 상태 동기화 ──
  Future<void> _syncFromRevenueCat() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
    } catch (_) {
      _cached ??= const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    final isPro   = info.entitlements.active.containsKey(_proEntitlement);
    final isBasic = info.entitlements.active.containsKey(_basicEntitlement);
    final tier = isPro
        ? PlanTier.pro
        : isBasic
            ? PlanTier.basic
            : PlanTier.free;
    _cached = SubscriptionInfo(
      status: (isPro || isBasic)
          ? SubscriptionStatus.active
          : SubscriptionStatus.free,
      tier: tier,
    );
    tierNotifier.value = _cached!.tier;
  }

  // ── 수동 갱신 ──
  Future<SubscriptionInfo> refresh(String uid) async {
    if (!kSubscriptionEnabled) return _cached!;
    await _syncFromRevenueCat();
    return _cached!;
  }

  // ── 베이직 구독 구매 ──
  Future<bool> purchaseBasic() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) return false;

      final package = current.availablePackages.firstWhere(
        (p) => p.storeProduct.identifier.contains('basic'),
        orElse: () => current.availablePackages.first,
      );

      final info = await Purchases.purchasePackage(package);
      _applyCustomerInfo(info);
      return _cached?.tier == PlanTier.basic;
    } on PurchasesError catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError) return false;
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── 프로 구독 구매 (할인 코드 적용 시 discountProductId 전달) ──
  Future<bool> purchasePro({String? discountProductId}) async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) return false;

      // 할인 상품 ID가 있으면 해당 상품 우선, 없으면 pro 포함 상품
      final package = current.availablePackages.firstWhere(
        (p) => discountProductId != null
            ? p.storeProduct.identifier == discountProductId
            : p.storeProduct.identifier.contains('pro'),
        orElse: () => current.availablePackages.firstWhere(
          (p) => p.storeProduct.identifier.contains('pro'),
          orElse: () => current.availablePackages.first,
        ),
      );

      final info = await Purchases.purchasePackage(package);
      _applyCustomerInfo(info);
      return _cached?.tier == PlanTier.pro;
    } on PurchasesError catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError) return false;
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── 구매 복원 ──
  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);
      return _cached?.tier != PlanTier.free;
    } catch (_) {
      return false;
    }
  }

  // ── 로그아웃 시 세션 초기화 ──
  void clearSession() {
    _initialized = false;
    _cached = null;
  }

  // ── 다른 사용자(사장님)의 tier 조회 ──
  static Future<PlanTier> fetchTierForUid(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final tierStr = doc.data()?['subscriptionTier'] as String? ?? 'free';
      if (tierStr == 'pro') return PlanTier.pro;
      if (tierStr == 'basic') return PlanTier.basic;
      return PlanTier.free;
    } catch (_) {
      return PlanTier.free;
    }
  }
}
