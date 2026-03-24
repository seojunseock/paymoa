// lib/screens/subscription_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────
// 구독 기능 플래그
// ─────────────────────────────────────────
/// false 로 설정 시 플랜 한도 강제 미적용
const kSubscriptionEnabled = true;

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
    maxWorkers: 4,
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
    monthlyPrice: 9000,
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

const _annualDiscountRate = 0.10;

// ─────────────────────────────────────────
// 공유 로직 믹스인
// ─────────────────────────────────────────
mixin _SubscriptionLogic<T extends StatefulWidget> on State<T> {
  bool _isAnnual = true; // 연간 기본 선택
  PlanTier? _selected;
  final _promoCtrl = TextEditingController();
  bool _promoLoading = false;
  String? _promoError;
  _PromoResult? _promoResult;

  // 연간 10% + 프로모 할인 누적
  double get _effectiveDiscount {
    final base = _isAnnual ? _annualDiscountRate : 0.0;
    final promo = _promoResult?.discountRate ?? 0.0;
    return (base + promo).clamp(0.0, 1.0);
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _promoLoading = true;
      _promoError = null;
      _promoResult = null;
    });
    try {
      final (result, errorMsg) = await _validatePromoCode(code);
      if (!mounted) return;
      if (result == null) {
        setState(() => _promoError = errorMsg ?? '유효하지 않은 코드예요.');
      } else {
        setState(() => _promoResult = result);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _promoError = '코드 확인 중 오류가 발생했어요.');
    } finally {
      if (mounted) setState(() => _promoLoading = false);
    }
  }

  Future<(_PromoResult?, String?)> _validatePromoCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return (null, '로그인이 필요해요.');

    final db = FirebaseFirestore.instance;
    final ref = db.collection('promoCodes').doc(code);
    final usedByRef = ref.collection('usedBy').doc(uid);

    _PromoResult? result;
    String? errorMsg;

    await db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        errorMsg = '유효하지 않은 코드예요.';
        return;
      }
      final data = doc.data()!;

      if (data['active'] == false) {
        errorMsg = '유효하지 않은 코드예요.';
        return;
      }

      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp &&
          expiresAt.toDate().isBefore(DateTime.now())) {
        errorMsg = '만료된 코드예요.';
        return;
      }

      final maxUses = data['maxUses'];
      if (maxUses != null) {
        final usedCount = (data['usedCount'] as num?)?.toInt() ?? 0;
        if (usedCount >= (maxUses as num).toInt()) {
          errorMsg = '사용 횟수가 초과된 코드예요.';
          return;
        }
      }

      // 이 사용자가 이미 사용했는지 확인
      final usedByDoc = await tx.get(usedByRef);
      if (usedByDoc.exists) {
        errorMsg = '이미 사용한 프로모션이에요.';
        return;
      }

      final pct = data['discountPercent'];
      if (pct == null) {
        errorMsg = '유효하지 않은 코드예요.';
        return;
      }

      result = _PromoResult(
        code: code,
        discountRate: (pct is num ? pct.toDouble() : 0.0) / 100.0,
        description: (data['description'] as String?) ?? '',
      );

      // 사용 횟수 증가 + 사용자 기록
      tx.update(ref, {'usedCount': FieldValue.increment(1)});
      tx.set(usedByRef, {'usedAt': FieldValue.serverTimestamp()});
    });

    return (result, errorMsg);
  }

  String _won(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return '$b원';
  }

  Widget _buildBillingToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ToggleBtn(
            label: '월간',
            active: !_isAnnual,
            onTap: () => setState(() => _isAnnual = false),
          ),
          _ToggleBtn(
            label: '연간  −10%',
            active: _isAnnual,
            onTap: () => setState(() => _isAnnual = true),
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPromoSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '프로모션 코드',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF111827),
                  ),
                  decoration: InputDecoration(
                    hintText: '코드 입력',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFD1D5DB),
                      letterSpacing: 0,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF7C3AED), width: 1.5),
                    ),
                    suffixIcon: _promoResult != null
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF10B981), size: 20)
                        : null,
                  ),
                  onSubmitted: (_) => _applyPromo(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _promoLoading ? null : _applyPromo,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: _promoLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '적용',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (_promoError != null) ...[
            const SizedBox(height: 8),
            Text(
              _promoError!,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFF43F5E)),
            ),
          ],
          if (_promoResult != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.local_offer_rounded,
                    size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Text(
                  '추가 ${(_promoResult!.discountRate * 100).round()}% 할인 적용됨'
                  '${_promoResult!.description.isNotEmpty ? "  ·  ${_promoResult!.description}" : ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubscribeButton(PlanTier currentTier) {
    final plan = kPlans.firstWhere((p) => p.tier == _selected,
        orElse: () => kPlans.first);
    final isCurrent = currentTier == _selected;
    final isFree = plan.monthlyPrice == 0;

    String label;
    if (isCurrent) {
      label = '현재 플랜';
    } else if (isFree) {
      label = '무료로 시작';
    } else {
      final price = _isAnnual
          ? '연 ${_won(plan.annualPrice(_effectiveDiscount))}'
          : '월 ${_won((plan.monthlyPrice * (1 - _effectiveDiscount)).round())}';
      label = '$price로 구독';
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: isCurrent
            ? null
            : () {
                // TODO: 실제 결제 연동
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('결제 기능은 곧 추가될 예정이에요.')),
                );
              },
        style: FilledButton.styleFrom(
          backgroundColor:
              isCurrent ? const Color(0xFFE5E7EB) : const Color(0xFF7C3AED),
          foregroundColor:
              isCurrent ? const Color(0xFF9CA3AF) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 전체 화면
// ─────────────────────────────────────────
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.currentTier = PlanTier.free,
  });

  final PlanTier currentTier;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with _SubscriptionLogic {
  @override
  void initState() {
    super.initState();
    _selected = widget.currentTier;
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _buildBillingToggle(),
          const SizedBox(height: 8),
          if (_isAnnual)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(
                child: Text(
                  '연간 결제 시 10% 할인',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade600,
                  ),
                ),
              ),
            ),
          ...kPlans.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanCard(
                  plan: p,
                  isSelected: _selected == p.tier,
                  isCurrent: widget.currentTier == p.tier,
                  isAnnual: _isAnnual,
                  discount: _effectiveDiscount,
                  won: _won,
                  onTap: () => setState(() => _selected = p.tier),
                ),
              )),
          const SizedBox(height: 8),
          _buildPromoSection(),
          const SizedBox(height: 24),
          _buildSubscribeButton(widget.currentTier),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// 바텀시트
// ─────────────────────────────────────────
class SubscriptionSheet extends StatefulWidget {
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscriptionSheet(currentTier: currentTier),
    );
  }

  @override
  State<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<SubscriptionSheet>
    with _SubscriptionLogic {
  @override
  void initState() {
    super.initState();
    _selected = widget.currentTier;
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
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
          // 핸들 바
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
          // 스크롤 가능한 콘텐츠
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(
                children: [
                  _buildBillingToggle(),
                  const SizedBox(height: 8),
                  if (_isAnnual)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Center(
                        child: Text(
                          '연간 결제 시 10% 할인',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ),
                    ),
                  ...kPlans.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PlanCard(
                          plan: p,
                          isSelected: _selected == p.tier,
                          isCurrent: widget.currentTier == p.tier,
                          isAnnual: _isAnnual,
                          discount: _effectiveDiscount,
                          won: _won,
                          onTap: () => setState(() => _selected = p.tier),
                        ),
                      )),
                  const SizedBox(height: 8),
                  _buildPromoSection(),
                  const SizedBox(height: 24),
                  _buildSubscribeButton(widget.currentTier),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// 플랜 카드
// ─────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isCurrent,
    required this.isAnnual,
    required this.discount,
    required this.won,
    required this.onTap,
  });

  final PlanInfo plan;
  final bool isSelected;
  final bool isCurrent;
  final bool isAnnual;
  final double discount;
  final String Function(int) won;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isFree = plan.monthlyPrice == 0;
    final borderColor =
        isSelected ? const Color(0xFF7C3AED) : const Color(0xFFE5E7EB);
    final bgColor = isSelected
        ? const Color(0xFF7C3AED).withOpacity(0.04)
        : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            // 라디오
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFFD1D5DB),
                  width: isSelected ? 6 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // 플랜 이름 + 한도
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF111827),
                        ),
                      ),
                      if (plan.badge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            plan.badge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '현재',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '매장 ${plan.maxStores}개  ·  알바생 ${plan.maxWorkers}명',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            // 가격
            if (isFree)
              const Text(
                '무료',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isAnnual && discount > 0) ...[
                    Text(
                      won(plan.monthlyPrice),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      '월 ${won(plan.annualMonthlyEquiv(discount))}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                    Text(
                      '연 ${won(plan.annualPrice(discount))}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ] else if (discount > 0 && !isAnnual) ...[
                    Text(
                      won(plan.monthlyPrice),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      '월 ${won((plan.monthlyPrice * (1 - discount)).round())}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                  ] else ...[
                    Text(
                      '월 ${won(plan.monthlyPrice)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 보조 위젯
// ─────────────────────────────────────────
class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7C3AED) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active
                  ? Colors.white
                  : highlight
                      ? Colors.green.shade600
                      : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 프로모션 결과 모델
// ─────────────────────────────────────────
class _PromoResult {
  final String code;
  final double discountRate; // 0.0 ~ 1.0
  final String description;

  const _PromoResult({
    required this.code,
    required this.discountRate,
    required this.description,
  });
}
