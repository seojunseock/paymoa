// lib/subscription/subscription_service.dart
//
// RevenueCat 기반 구독 상태 관리.
// kSubscriptionEnabled = false 이면 모든 로직이 no-op 으로 동작.
//
// ── 연동 구조 ────────────────────────────────────────────────────────────────
// [자신]  RevenueCat.getCustomerInfo() → entitlements → PlanTier
// [타인]  Firestore users/{uid}.subscriptionTier (구매 시 자동 동기화)
// ──────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../screens/subscription_screen.dart';

// ─────────────────────────────────────────
// 구독 상태
// ─────────────────────────────────────────
enum SubscriptionStatus {
  active,       // 정상 구독 중
  gracePeriod,  // 결제 문제 감지, 유예기간 중 — 기능 전체 유지
  expired,      // 유예기간 종료 → 무료 플랜으로 자동 다운그레이드
  free,         // 구독 없음 (무료 플랜)
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
    return gracePeriodEndsAt!
        .difference(DateTime.now())
        .inDays
        .clamp(0, 3);
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
  bool _shouldShowWarning = false;

  SubscriptionInfo? get cached => _cached;
  bool get shouldShowBillingWarning => _shouldShowWarning;

  // ── 초기화 (앱 시작 / 로그인 시 1회) ────
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

    try {
      _cached = await _fetchInfo(uid);
    } catch (e) {
      debugPrint('[SubscriptionService] init error: $e');
      _cached = const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }
  }

  // ── 수동 갱신 (구독 화면에서 플랜 변경 후 호출) ─
  Future<SubscriptionInfo> refresh(String uid) async {
    if (!kSubscriptionEnabled) return _cached!;
    _initialized = false; // 재조회 허용
    try {
      _cached = await _fetchInfo(uid);
    } catch (e) {
      debugPrint('[SubscriptionService] refresh error: $e');
    }
    return _cached ??
        const SubscriptionInfo(
          status: SubscriptionStatus.free,
          tier: PlanTier.free,
        );
  }

  // ── 로그아웃 시 세션 초기화 ──────────────
  void clearSession() {
    _initialized = false;
    _cached = null;
    _shouldShowWarning = false;
  }

  // ─────────────────────────────────────────
  // 내부: RevenueCat에서 내 구독 상태 읽기 + Firestore 동기화
  // ─────────────────────────────────────────
  Future<SubscriptionInfo> _fetchInfo(String uid) async {
    final customerInfo = await Purchases.getCustomerInfo();
    final active = customerInfo.entitlements.active;

    PlanTier tier;
    if (active.containsKey('business')) {
      tier = PlanTier.business;
    } else if (active.containsKey('pro')) {
      tier = PlanTier.pro;
    } else if (active.containsKey('classic')) {
      tier = PlanTier.classic;
    } else {
      tier = PlanTier.free;
    }

    // 타인이 참조할 수 있도록 Firestore에도 동기화
    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'subscriptionTier': _tierToString(tier)},
      SetOptions(merge: true),
    );

    final status = tier == PlanTier.free
        ? SubscriptionStatus.free
        : SubscriptionStatus.active;

    return SubscriptionInfo(status: status, tier: tier);
  }

  // ─────────────────────────────────────────
  // 다른 사용자(사장님)의 tier 조회 — join_store_sheet 등에서 사용
  // ─────────────────────────────────────────
  static Future<PlanTier> fetchTierForUid(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final tierStr = doc.data()?['subscriptionTier'] as String? ?? 'free';
      return instance._tierFromString(tierStr);
    } catch (_) {
      return PlanTier.free;
    }
  }

  PlanTier _tierFromString(String s) {
    switch (s) {
      case 'classic': return PlanTier.classic;
      case 'pro': return PlanTier.pro;
      case 'business': return PlanTier.business;
      default: return PlanTier.free;
    }
  }

  String _tierToString(PlanTier tier) {
    switch (tier) {
      case PlanTier.classic: return 'classic';
      case PlanTier.pro: return 'pro';
      case PlanTier.business: return 'business';
      default: return 'free';
    }
  }
}
