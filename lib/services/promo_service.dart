// lib/services/promo_service.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PromoResult {
  success,   // 코드 적용 성공
  discount,  // 할인 코드 적용 성공
  invalid,   // 존재하지 않거나 비활성화된 코드
  already,   // 이미 적용된 코드
  error,     // 네트워크 등 오류
}

class PromoService {
  static final PromoService instance = PromoService._();
  PromoService._();

  static const _keyAdFree          = 'promo_ad_free';
  static const _keyProGranted       = 'promo_pro_granted';
  static const _keyDiscountPercent  = 'promo_discount_percent';
  static const _keyDiscountProduct  = 'promo_discount_product_id';

  bool    _adFree       = false;
  bool    _proGranted   = false;
  int?    _discountPercent;
  String? _discountProductId;

  bool    get isAdFree          => _adFree;
  bool    get isProGranted      => _proGranted;
  bool    get hasDiscount       => _discountPercent != null;
  int?    get discountPercent   => _discountPercent;
  String? get discountProductId => _discountProductId;

  /// 배너가 즉시 사라지도록 AdBannerWidget이 listen하는 notifier
  final adFreeNotifier = ValueNotifier<bool>(false);

  // ── 앱 시작 시 1회 초기화 ──
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _adFree          = prefs.getBool(_keyAdFree)         ?? false;
    _proGranted      = prefs.getBool(_keyProGranted)      ?? false;
    _discountPercent = prefs.getInt(_keyDiscountPercent);
    _discountProductId = prefs.getString(_keyDiscountProduct);
    adFreeNotifier.value = _adFree;
  }

  // ── 코드 검증 및 적용 ──
  Future<PromoResult> applyCode(String raw) async {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return PromoResult.invalid;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('promo_codes')
          .where('code', isEqualTo: code)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return PromoResult.invalid;

      final data = snap.docs.first.data();
      final type = data['type'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();

      switch (type) {
        case 'ad_free':
          if (_adFree) return PromoResult.already;
          _adFree = true;
          adFreeNotifier.value = true; // 배너 즉시 제거
          await prefs.setBool(_keyAdFree, true);
          return PromoResult.success;

        case 'grant_pro':
          if (_proGranted) return PromoResult.already;
          _proGranted = true;
          await prefs.setBool(_keyProGranted, true);
          return PromoResult.success;

        case 'discount':
          if (hasDiscount) return PromoResult.already;
          final percent   = (data['discountPercent'] as num?)?.toInt() ?? 0;
          final productId = data['discountProductId'] as String?;
          _discountPercent   = percent;
          _discountProductId = productId;
          await prefs.setInt(_keyDiscountPercent, percent);
          if (productId != null) {
            await prefs.setString(_keyDiscountProduct, productId);
          }
          return PromoResult.discount;

        default:
          return PromoResult.invalid;
      }
    } catch (_) {
      return PromoResult.error;
    }
  }
}
