// lib/common/paymoa_design.dart
//
// ═══════════════════════════════════════════════════════════
//  PAYMOA DESIGN DNA
//
//  배경: 순백 #FFFFFF
//  포인트: 바이올렛 #7C3AED  (국내 급여앱 최초 소유)
//  급여/성공: 에메랄드 #059669  (돈 = 그린)
//  삭제/위험: 로즈 #F43F5E
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class Pm {
  // ── 메인 ────────────────────────────────────
  static const primary = Color(0xFF7C3AED); // 바이올렛
  static const primarySoft = Color(0xFF9333EA); // 연보라 (뱃지용)

  // ── 기능 ────────────────────────────────────
  static const money = Color(0xFF059669); // 급여·성공
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFF43F5E);

  // ── 배경 ────────────────────────────────────
  static const bg = Color(0xFFFFFFFF); // 순백
  static const card = Color(0xFFFFFFFF);
  static const fieldBg = Color(0xFFF9F8FF); // 입력 필드 살짝 보라 틴트

  // ── 텍스트 ──────────────────────────────────
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);

  // ── 선 ──────────────────────────────────────
  static const border = Color(0xFFF3F4F6);
  static const divider = Color(0xFFE5E7EB);

  // ── 카드 그림자 ──────────────────────────────
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF7C3AED).withOpacity(0.06),
      blurRadius: 0,
      spreadRadius: 1,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: const Color(0xFF000000).withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // ── 반경 ────────────────────────────────────
  static const radiusCard = 16.0;
  static const radiusInner = 10.0;
  static const radiusBtn = 14.0;
  static const accentBarWidth = 4.0;
}

// ─── PaymoaColors 별칭 (alba_start_screen 호환) ─
class PaymoaColors {
  static const primary = Pm.primary;
  static const primarySoft = Pm.primarySoft;
  static const secondary = Pm.primarySoft;
  static const success = Pm.money;
  static const warning = Pm.warning;
  static const error = Pm.danger;
  static const background = Pm.bg;
  static const surfaceLight = Pm.fieldBg;
  static const card = Pm.card;
  static const textPrimary = Pm.textPrimary;
  static const textSecondary = Pm.textSecondary;
  static const textTertiary = Pm.textTertiary;
  static const border = Pm.border;
  static const divider = Pm.divider;
}

// ─── 목록 카드 (알바·매장 공용) ─────────────────
class PmCard extends StatelessWidget {
  const PmCard({
    super.key,
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.onTap,
  });
  final Widget child;
  final Color accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        decoration: BoxDecoration(
          color: Pm.card,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(Pm.radiusCard),
          ),
          border: Border.all(color: Pm.border, width: 1),
          boxShadow: Pm.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(Pm.radiusCard)),
            splashColor: accent.withOpacity(0.04),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left + Pm.accentBarWidth,
                padding.top,
                padding.right,
                padding.bottom,
              ),
              child: child,
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 7,
        bottom: 7,
        child: Container(
          width: Pm.accentBarWidth,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── 폼 섹션 카드 ────────────────────────────────
class PmFormCard extends StatelessWidget {
  const PmFormCard({super.key, required this.child, this.label, this.trailing});
  final Widget child;
  final String? label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Pm.card,
        borderRadius: BorderRadius.circular(Pm.radiusCard),
        border: Border.all(color: Pm.border, width: 1),
        boxShadow: Pm.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(children: [
              Text(label!,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Pm.textTertiary,
                      letterSpacing: 0.6)),
              const Spacer(),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 10),
          ] else if (trailing != null) ...[
            Align(alignment: Alignment.centerRight, child: trailing!),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

// ─── kv 행 ──────────────────────────────────────
Widget pmKv(String k, String v, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(
          child: Text(k,
              style: const TextStyle(
                  fontSize: 16,
                  color: Pm.textSecondary,
                  fontWeight: FontWeight.w500))),
      Text(v,
          textAlign: TextAlign.right,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Pm.textPrimary)),
    ]),
  );
}

// ─── 삭제·수정 버튼 행 ───────────────────────────
Widget pmActionRow({
  required VoidCallback onDelete,
  required VoidCallback onEdit,
}) {
  return SizedBox(
    height: 52,
    child: Row(children: [
      Expanded(
        child: TextButton.icon(
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline_rounded,
              size: 16, color: Pm.danger.withOpacity(0.75)),
          label: Text('삭제',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Pm.danger.withOpacity(0.75))),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ),
      Container(width: 1, height: 22, color: Pm.divider),
      Expanded(
        child: TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined,
              size: 16, color: Pm.textSecondary),
          label: const Text('수정',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Pm.textSecondary)),
          style: TextButton.styleFrom(
              foregroundColor: Pm.textSecondary,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ),
    ]),
  );
}

// ─── 색상 파서 ───────────────────────────────────
Color pmColor(String? hex, {Color fallback = Pm.primary}) {
  if (hex == null || hex.isEmpty) return fallback;
  try {
    return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
  } catch (_) {
    return fallback;
  }
}
