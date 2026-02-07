// lib/data/stats_repository.dart
import 'dart:math';

import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';
import '../payroll/payroll.dart';

class MonthlyIncomePoint {
  final DateTime month; // 해당 월의 1일
  final int amount; // 해당 월 총액(원) — 기본: 세후(net)
  const MonthlyIncomePoint({required this.month, required this.amount});
}

class StatsRepository {
  const StatsRepository();

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

    // ✅ month underflow 안전 처리: DateTime(year, month +/- n) 사용
    final months = List<DateTime>.generate(4, (i) {
      final m = DateTime(base.year, base.month - (3 - i), 1);
      return DateTime(m.year, m.month, 1);
    });

    final Map<String, int> sumByYm = {for (final m in months) _ymKey(m): 0};

    for (final m in months) {
      final ymYear = m.year;
      final ymMonth = m.month;

      int monthTotal = 0;

      for (final a in albas) {
        final tax = taxOf(a.id) ?? TaxConfig.none;
        final ins = insuranceOf(a.id) ?? const InsuranceNone();
        final pol = policyOf(a.id) ?? const SurchargePolicy();

        final monthSchedules = schedules
            .where((s) =>
                s.albaId == a.id && s.year == ymYear && s.month == ymMonth)
            .toList();

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

        monthTotal += summary.net;
      }

      sumByYm[_ymKey(m)] = monthTotal;
    }

    return months
        .map((m) =>
            MonthlyIncomePoint(month: m, amount: sumByYm[_ymKey(m)] ?? 0))
        .toList();
  }

  List<double> synthesizeCohortAverage(
    List<MonthlyIncomePoint> mine, {
    int? ageSeed,
  }) {
    if (mine.isEmpty) return const [0, 0, 0, 0];
    final seed = (ageSeed ?? 25) + mine.last.amount;
    final rnd = Random(seed);

    return mine
        .map((p) => max(0, p.amount * (0.85 + rnd.nextDouble() * 0.2)))
        .map((v) => (v / 100).roundToDouble() * 100)
        .toList();
  }

  String _ymKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
