// lib/ads/ad_service.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// ignore_for_file: unused_field

class _AdIds {
  // ── 테스트 ID ──
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  // ── 실제 ID (Android) ──
  static const _realBannerAndroid = 'ca-app-pub-2756061286403249/1086876298';
  static const _realRewardedAndroid = 'ca-app-pub-2756061286403249/6982200803';
  static const _realInterstitialAndroid = 'ca-app-pub-2756061286403249/5629110129';

  // ── 실제 ID (iOS) ──
  static const _realBannerIos = 'ca-app-pub-2756061286403249/5970204095';
  static const _realRewardedIos = 'ca-app-pub-2756061286403249/1636419446';
  static const _realInterstitialIos = 'ca-app-pub-2756061286403249/1316643211';

  // ✅ 테스트 중: true / 출시 전: false 로 변경
  static bool get _isTest => true;

  static String get banner {
    if (_isTest) return _testBanner;
    return Platform.isIOS ? _realBannerIos : _realBannerAndroid;
  }

  static String get rewarded {
    if (_isTest) return _testRewarded;
    return Platform.isIOS ? _realRewardedIos : _realRewardedAndroid;
  }

  static String get interstitial {
    if (_isTest) return _testInterstitial;
    return Platform.isIOS ? _realInterstitialIos : _realInterstitialAndroid;
  }
}

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  bool _interstitialPendingShow = false; // 로드 완료 즉시 표시 플래그

  DateTime? _adFreeUntil;

  bool get isAdFree =>
      _adFreeUntil != null && _adFreeUntil!.isAfter(DateTime.now());

  void setAdFreeUntil(DateTime? dt) {
    _adFreeUntil = dt;
  }

  /// 광고가 준비되면 즉시 표시. 로드 중이면 완료 후 자동 표시.
  /// AppShell 진입 시 호출 — 신규 사용자(로그인 화면)는 호출하지 않음.
  void requestShowWhenReady() {
    if (_interstitialAd != null) {
      showInterstitialAd();
    } else {
      _interstitialPendingShow = true;
    }
  }

  void preloadInterstitialAd({bool autoShow = false}) {
    if (_interstitialAd != null || _isInterstitialLoading) return;
    _isInterstitialLoading = true;
    if (autoShow) _interstitialPendingShow = true;

    InterstitialAd.load(
      adUnitId: _AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
          debugPrint('[AdService] 인터스티셜 광고 로드 완료');
          if (_interstitialPendingShow) {
            _interstitialPendingShow = false;
            showInterstitialAd();
          }
        },
        onAdFailedToLoad: (error) {
          _isInterstitialLoading = false;
          _interstitialPendingShow = false;
          debugPrint('[AdService] 인터스티셜 광고 로드 실패: $error');
        },
      ),
    );
  }

  Future<void> showInterstitialAd({VoidCallback? onDismissed}) async {
    if (isAdFree) {
      debugPrint('[AdService] 광고 면제 기간 → 인터스티셜 스킵');
      onDismissed?.call();
      return;
    }
    if (_interstitialAd == null) {
      debugPrint('[AdService] 인터스티셜 준비 안 됨 → 스킵');
      onDismissed?.call();
      preloadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        preloadInterstitialAd();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        preloadInterstitialAd();
        debugPrint('[AdService] 인터스티셜 표시 실패: $error');
        onDismissed?.call();
      },
    );

    await _interstitialAd!.show();
  }

  void preloadRewardedAd() {
    if (_rewardedAd != null || _isLoading) return;
    _isLoading = true;

    RewardedAd.load(
      adUnitId: _AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          debugPrint('[AdService] 리워드 광고 로드 완료');
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          debugPrint('[AdService] 리워드 광고 로드 실패: $error');
        },
      ),
    );
  }

  Future<void> showRewardedAd({
    required VoidCallback onRewarded,
    VoidCallback? onDismissed,
    VoidCallback? onNotReady,
  }) async {
    if (isAdFree) {
      debugPrint('[AdService] 광고 면제 기간 → 리워드 스킵, 바로 실행');
      onRewarded();
      return;
    }
    if (_rewardedAd == null) {
      debugPrint('[AdService] 광고 준비 안 됨 → 즉시 실행');
      onNotReady?.call();
      preloadRewardedAd();
      return;
    }

    bool rewarded = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        preloadRewardedAd();
        if (rewarded) onRewarded();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        preloadRewardedAd();
        debugPrint('[AdService] 광고 표시 실패: $error');
        onDismissed?.call();
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (_, reward) {
        rewarded = true;
      },
    );
  }
}

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final ad = BannerAd(
      adUnitId: _AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('[AdBanner] 로드 실패: $error');
        },
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
