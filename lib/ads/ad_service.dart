// lib/ads/ad_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();
  static final instance = AdService._();

  // ── 광고 단위 ID ──
  static String get _interstitialId => Platform.isIOS
      ? 'ca-app-pub-2756061286403249/3089438621' // TODO: iOS 전면광고 ID로 교체
      : 'ca-app-pub-2756061286403249/3089438621';

  static String get _rewardId => Platform.isIOS
      ? 'ca-app-pub-2756061286403249/7052734360' // TODO: iOS 리워드 ID로 교체
      : 'ca-app-pub-2756061286403249/7052734360';

  static String get _bannerId => Platform.isIOS
      ? 'ca-app-pub-2756061286403249/6645540255' // TODO: iOS 배너 ID로 교체
      : 'ca-app-pub-2756061286403249/6645540255';

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
  }

  // ── 전면광고 미리 로드 ──
  void _loadInterstitial() {
    if (_isInterstitialLoading) return;
    _isInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
        },
        onAdFailedToLoad: (_) {
          _isInterstitialLoading = false;
        },
      ),
    );
  }

  // ── 전면광고 표시 (닫힌 후 onAdClosed 실행) ──
  Future<void> showInterstitial({required VoidCallback onAdClosed}) async {
    final ad = _interstitialAd;
    if (ad == null) {
      onAdClosed();
      _loadInterstitial();
      return;
    }
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onAdClosed();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        onAdClosed();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  // ── 리워드광고 표시 (보상 지급 후 onRewarded 실행) ──
  Future<void> showRewardAd({required VoidCallback onRewarded}) async {
    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: _rewardId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          bool rewarded = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              if (rewarded) onRewarded();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              onRewarded();
              if (!completer.isCompleted) completer.complete();
            },
          );
          ad.show(onUserEarnedReward: (_, __) => rewarded = true);
        },
        onAdFailedToLoad: (_) {
          onRewarded();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    return completer.future;
  }

  // ── 배너광고 위젯 ──
  BannerAd createBannerAd() => BannerAd(
        adUnitId: _bannerId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: const BannerAdListener(),
      );
}

// ── 배너 위젯 ──
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  late final BannerAd _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdService._bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: _ad.size.width.toDouble(),
      height: _ad.size.height.toDouble(),
      child: AdWidget(ad: _ad),
    );
  }
}
