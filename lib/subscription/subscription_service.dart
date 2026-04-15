// lib/subscription/subscription_service.dart
//
// 구독 상태 관리 (RevenueCat 제거됨 - 추후 재연동 예정)
//
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final bool _shouldShowWarning = false;

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

    // RevenueCat 제거됨: 항상 무료 플랜
    _cached = const SubscriptionInfo(
      status: SubscriptionStatus.free,
      tier: PlanTier.free,
    );
  }

  // ── 수동 갱신 ─
  Future<SubscriptionInfo> refresh(String uid) async {
    if (!kSubscriptionEnabled) return _cached!;
    _initialized = false;
    _cached = const SubscriptionInfo(
      status: SubscriptionStatus.free,
      tier: PlanTier.free,
    );
    return _cached!;
  }

  // ── 로그아웃 시 세션 초기화 ──────────────
  void clearSession() {
    _initialized = false;
    _cached = null;
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
}
