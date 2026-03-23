// lib/subscription/subscription_service.dart
//
// RevenueCat 기반 구독 상태 관리.
// kSubscriptionEnabled = false 이면 모든 로직이 no-op 으로 동작.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../screens/subscription_screen.dart';

// ─────────────────────────────────────────
// 구독 상태
// ─────────────────────────────────────────
enum SubscriptionStatus {
  active,       // 정상 구독 중
  gracePeriod,  // 결제 문제 감지, 유예기간(3일) 중 — 기능 전체 유지
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

  /// 유예기간 종료 또는 구독 없음 → 무료 한도 적용
  bool get isReadOnlyMode => status == SubscriptionStatus.expired;

  /// 유예기간 남은 일수 (0~3)
  int get remainingGraceDays {
    if (gracePeriodEndsAt == null) return 0;
    return gracePeriodEndsAt!
        .difference(DateTime.now())
        .inDays
        .clamp(0, _graceDays);
  }
}

// ─────────────────────────────────────────
// 서비스 (싱글톤)
// ─────────────────────────────────────────
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  // ── RevenueCat API 키 ────────────────────
  // TODO: 실제 키로 교체 (RevenueCat 대시보드 > API Keys)
  static const _rcAndroidKey = 'goog_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
  static const _rcIosKey = 'appl_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

  /// RevenueCat 엔타이틀먼트 ID (대시보드에서 설정한 이름과 일치해야 함)
  static const _entitlementId = 'premium';

  SubscriptionInfo? _cached;
  bool _initialized = false;
  bool _shouldShowWarning = false; // 이번 앱 세션에 결제 경고 팝업 띄울지

  SubscriptionInfo? get cached => _cached;
  bool get shouldShowBillingWarning => _shouldShowWarning;

  // ── 초기화 (앱 시작 / 로그인 시 1회) ────
  Future<void> init(String uid) async {
    if (!kSubscriptionEnabled) {
      // 구독 비활성화: 항상 active/free 처리
      _cached = const SubscriptionInfo(
        status: SubscriptionStatus.active,
        tier: PlanTier.free,
      );
      return;
    }
    if (_initialized) return;
    _initialized = true;

    try {
      await Purchases.setLogLevel(LogLevel.warn);
      final config = PurchasesConfiguration(
        Platform.isAndroid ? _rcAndroidKey : _rcIosKey,
      )..appUserID = uid;
      await Purchases.configure(config);

      _cached = await _fetchInfo(uid);

      if (_cached!.hasBillingIssue) {
        _shouldShowWarning = true;
      }
    } catch (e) {
      debugPrint('[SubscriptionService] init error: $e');
      // RC 오류 시 무료 플랜으로 안전 폴백
      _cached = const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }
  }

  // ── 수동 갱신 (구독 화면에서 저장 후 호출) ─
  Future<SubscriptionInfo> refresh(String uid) async {
    if (!kSubscriptionEnabled) return _cached!;
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
  // 내부: RevenueCat 조회 + 유예기간 계산
  // ─────────────────────────────────────────
  Future<SubscriptionInfo> _fetchInfo(String uid) async {
    final db = FirebaseFirestore.instance;
    final subRef = db
        .collection('users')
        .doc(uid)
        .collection('subscription')
        .doc('status');

    late CustomerInfo ci;
    try {
      ci = await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('[SubscriptionService] getCustomerInfo error: $e');
      return const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }

    final entitlement = ci.entitlements.all[_entitlementId];
    final isActive = entitlement?.isActive ?? false;
    final hasBillingIssue = entitlement?.billingIssueDetectedAt != null;

    // ── 구독 없음 ────────────────────────────
    if (entitlement == null) {
      return const SubscriptionInfo(
        status: SubscriptionStatus.free,
        tier: PlanTier.free,
      );
    }

    // ── 정상 구독 ────────────────────────────
    if (isActive && !hasBillingIssue) {
      // 결제 문제 기록 초기화
      await subRef
          .set({'rcStatus': 'active', 'billingIssueDetectedAt': null},
              SetOptions(merge: true))
          .catchError((_) {});
      return SubscriptionInfo(
        status: SubscriptionStatus.active,
        tier: _tierFrom(ci),
      );
    }

    // ── 결제 문제 (expired or billing_issue) ──
    // Firestore에서 최초 감지 시각 조회 → 유예기간 계산
    final snap = await subRef.get();
    final data = snap.data() ?? {};

    DateTime billingIssueFirst;
    if (data['billingIssueDetectedAt'] is Timestamp) {
      billingIssueFirst =
          (data['billingIssueDetectedAt'] as Timestamp).toDate();
    } else {
      // 최초 감지 → 타임스탬프 기록
      billingIssueFirst = DateTime.now();
      await subRef.set(
        {
          'billingIssueDetectedAt': Timestamp.fromDate(billingIssueFirst),
          'gracePeriodEndsAt': Timestamp.fromDate(
              billingIssueFirst.add(const Duration(days: _graceDays))),
          'rcStatus': 'billingIssue',
        },
        SetOptions(merge: true),
      );
    }

    final gracePeriodEndsAt =
        billingIssueFirst.add(const Duration(days: _graceDays));
    final now = DateTime.now();
    final prevTier = _tierFrom(ci);

    if (now.isBefore(gracePeriodEndsAt)) {
      // 유예기간 중 — 이전 플랜 그대로 유지
      return SubscriptionInfo(
        status: SubscriptionStatus.gracePeriod,
        tier: prevTier,
        gracePeriodEndsAt: gracePeriodEndsAt,
        hasBillingIssue: true,
      );
    } else {
      // 유예기간 종료 → 무료로 다운그레이드
      await subRef
          .set({'rcStatus': 'downgraded'}, SetOptions(merge: true))
          .catchError((_) {});
      return SubscriptionInfo(
        status: SubscriptionStatus.expired,
        tier: PlanTier.free,
        gracePeriodEndsAt: gracePeriodEndsAt,
        hasBillingIssue: true,
      );
    }
  }

  // TODO: 실제 RevenueCat product / entitlement ID에 맞게 매핑 수정
  PlanTier _tierFrom(CustomerInfo ci) {
    final ids = ci.activeSubscriptions;
    if (ids.any((id) => id.contains('business'))) return PlanTier.business;
    if (ids.any((id) => id.contains('pro'))) return PlanTier.pro;
    if (ids.any((id) => id.contains('classic'))) return PlanTier.classic;
    if (ci.entitlements.active.containsKey(_entitlementId)) {
      return PlanTier.classic; // 폴백
    }
    return PlanTier.free;
  }
}

// 외부에서 접근 가능한 상수
const _graceDays = 3;

