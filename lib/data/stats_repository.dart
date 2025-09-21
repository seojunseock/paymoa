// lib/data/stats_repository.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';
import '../payroll/payroll.dart';

/// 막대그래프 1칸(해당 월 세후 총액)을 표현하는 데이터
class MonthlyIncomePoint {
  final DateTime month; // 해당 월의 1일 (레이블용)
  final int amount;     // 해당 월 총액(원) — 기본: 세후(net)
  const MonthlyIncomePoint({required this.month, required this.amount});
}

/// 통계 산출 전용 리포지터리:
/// - 스케줄/시급/정책을 바탕으로 “최근 4개월 월급 합계(세후)”를 계산합니다.
/// - 월 합계는 “알바별 월 정산 결과(net)”를 모두 합산한 값입니다.
/// - 오버나이트/휴게/가산정책/세금·보험은 computeMonthlySummary()에 위임합니다.
class StatsRepository {
  const StatsRepository();

  /// 최근 4개월(오래된→최근) “세후(net)” 합계를 계산.
  ///
  /// [albas]        : 등록된 알바 목록
  /// [schedules]    : 모든 스케줄
  /// [wageAt]       : 날짜별 시급 스냅샷 조회 (albaId, localDate) -> wage
  /// [taxOf]        : 알바별 세금 설정 조회
  /// [insuranceOf]  : 알바별 보험 설정 조회
  /// [policyOf]     : 알바별 가산정책(연장/야간/휴일/주휴 등) 조회
  /// [now]          : 기준일(기본: DateTime.now())
  ///
  /// 반환: 오래된→최근 순 4개. 각 원소는 (해당 월 1일, 그 달 총액).
  List<MonthlyIncomePoint> last4MonthsNet({
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
    required int Function(String albaId, DateTime dateLocal) wageAt,
    required TaxConfig? Function(String albaId) taxOf,
    required InsuranceConfig? Function(String albaId) insuranceOf,
    required SurchargePolicy? Function(String albaId) policyOf,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();

    // 최근 4개월(오래된→최근) 목록
    final months = List<DateTime>.generate(4, (i) {
      final m = DateTime(base.year, base.month - (3 - i), 1);
      return DateTime(m.year, m.month, 1);
    });

    // 월별 합계 매핑
    final Map<String, int> sumByYm = {for (final m in months) _ymKey(m): 0};

    // 각 월에 대해 알바별 정산 후 합산(세후)
    for (final m in months) {
      final ymYear = m.year;
      final ymMonth = m.month;

      int monthTotal = 0;
      for (final a in albas) {
        final tax = taxOf(a.id) ?? TaxConfig.none;
        final ins = insuranceOf(a.id) ?? const InsuranceNone();
        final pol = policyOf(a.id) ?? const SurchargePolicy();

        // 해당 알바의 해당 월 스케줄만 필터
        final monthSchedules = schedules.where((s) =>
          s.albaId == a.id && s.year == ymYear && s.month == ymMonth).toList();
        if (monthSchedules.isEmpty) continue;

        final summary = computeMonthlySummary(
          alba: a,
          ymYear: ymYear,
          ymMonth: ymMonth,
          schedules: monthSchedules,
          tax: tax,
          insurance: ins,
          policy: pol,
          wageAt: wageAt,
        );

        // 바는 '세후' 권장 (세전 쓰려면 summary.gross 로 변경)
        monthTotal += summary.net;
      }

      sumByYm[_ymKey(m)] = monthTotal;
    }

    // 오래된→최근 순으로 반환
    return months
        .map((m) => MonthlyIncomePoint(month: m, amount: sumByYm[_ymKey(m)] ?? 0))
        .toList();
  }

  /// (임시) 나이대 평균 꺾은선 데이터를 서버 집계 없이 합성해서 사용.
  /// 실제 서비스에서는 Firestore/CF로 같은 나이대 사용자들의 월합 평균을 받아 쓰세요.
  List<double> synthesizeCohortAverage(
    List<MonthlyIncomePoint> mine, {
    int? ageSeed,
  }) {
    if (mine.isEmpty) return const [0, 0, 0, 0];
    final seed = (ageSeed ?? 25) + mine.last.amount;
    final rnd = Random(seed);

    // 85%~105% 범위에서 살짝 흔들고, 100원 단위 반올림
    return mine
        .map((p) => max(0, p.amount * (0.85 + rnd.nextDouble() * 0.2)))
        .map((v) => (v / 100).roundToDouble() * 100)
        .toList();
  }

  String _ymKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
