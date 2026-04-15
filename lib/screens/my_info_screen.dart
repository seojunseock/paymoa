// lib/screens/my_info_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../common/app_words.dart';
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

class MyInfoMonthlyNetPoint {
  final int year;
  final int month;
  final int net;

  const MyInfoMonthlyNetPoint({
    required this.year,
    required this.month,
    required this.net,
  });
}

class _MonthPoint {
  final int year;
  final int month;
  final int net;

  const _MonthPoint({
    required this.year,
    required this.month,
    required this.net,
  });

  String get label => '${month}월';
}

class MyInfoScreen extends StatefulWidget {
  const MyInfoScreen({
    super.key,
    required this.albas,
    required this.schedules,
    required this.wageAt,
    required this.taxOf,
    required this.insuranceOf,
    required this.policyOf,
    this.surchargeAt,
    this.userAge,
    required this.payDay,
    this.onLogout,
    this.onDeleteAccount,
    this.onOpenTerms,
    this.onOpenPrivacy,
    this.onOpenSupport,
    this.monthlyNetPoints = const [],
  });

  // ✅ 기존 호출부와의 호환을 위해 유지
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final int Function(String albaId, DateTime dateLocal) wageAt;
  final TaxConfig? Function(String albaId) taxOf;
  final InsuranceConfig? Function(String albaId) insuranceOf;
  final SurchargePolicy? Function(String albaId) policyOf;
  final SurchargePolicy Function(DateTime)? Function(String albaId)?
      surchargeAt;
  final int? userAge;
  final int payDay;

  // ✅ 실제 그래프는 이 값만 사용
  final List<MyInfoMonthlyNetPoint> monthlyNetPoints;

  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenSupport;

  @override
  State<MyInfoScreen> createState() => _MyInfoScreenState();
}

class _MyInfoScreenState extends State<MyInfoScreen> {
  List<_MonthPoint> _points = const [];
  int _touchedIndex = -1;

  @override
  void initState() {
    super.initState();
    _syncPoints();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MyInfoScreen old) {
    super.didUpdateWidget(old);
    if (!_sameMonthlyPoints(old.monthlyNetPoints, widget.monthlyNetPoints)) {
      _syncPoints();
    }
  }

  void _syncPoints() {
    final sorted = [...widget.monthlyNetPoints]..sort((a, b) {
        final ak = a.year * 100 + a.month;
        final bk = b.year * 100 + b.month;
        return ak.compareTo(bk);
      });

    final latest3 = sorted.length <= 3
        ? sorted
        : sorted.sublist(sorted.length - 3, sorted.length);

    final points = latest3
        .map((e) => _MonthPoint(year: e.year, month: e.month, net: e.net))
        .toList(growable: false);

    if (!mounted) {
      _points = points;
      return;
    }

    setState(() {
      _points = points;
      if (_touchedIndex >= _points.length) {
        _touchedIndex = -1;
      }
    });
  }

  bool _sameMonthlyPoints(
    List<MyInfoMonthlyNetPoint> a,
    List<MyInfoMonthlyNetPoint> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].year != b[i].year ||
          a[i].month != b[i].month ||
          a[i].net != b[i].net) {
        return false;
      }
    }
    return true;
  }

  Future<void> _safeLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppWords.logoutConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppWords.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              AppWords.logout,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (widget.onLogout != null) {
      widget.onLogout!.call();
      return;
    }

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppWords.logoutDone)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  String _won(int n) {
    if (n == 0) return '0원';
    final man = n ~/ 10000;
    final rest = n % 10000;
    if (man > 0 && rest == 0) return '$man만원';
    if (man > 0) return '$man만 ${_comma(rest)}원';
    return '${_comma(n)}원';
  }

  String _wonAxis(int n) {
    if (n < 10000) return '${_comma(n)}';
    return '${n ~/ 10000}만';
  }

  String _comma(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          '내 정보',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildIncomeCard(),
          const SizedBox(height: 16),
          _buildPolicyCard(),
          const SizedBox(height: 12),
          _buildFaqSupportCard(),
          const SizedBox(height: 12),
          _buildDangerZoneCard(),
        ],
      ),
    );
  }

  Widget _buildIncomeCard() {
    final theme = Theme.of(context);
    final hasData = _points.any((p) => p.net > 0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF7C3AED),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3개월 실수령',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  Text(
                    '앞 화면에서 계산된 최종 금액',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_points.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '이번 달',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                    Text(
                      _won(_points.last.net),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (!hasData)
            SizedBox(
              height: 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.show_chart_rounded,
                    size: 36,
                    color: const Color(0xFF9CA3AF).withOpacity(0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '아직 표시할 급여가 없어요',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(height: 180, child: _buildLineChart(theme)),
          if (hasData) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _points.map((p) {
                      final isLast = p == _points.last;
                      return Text(
                        p.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isLast
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF6B7280),
                          fontWeight:
                              isLast ? FontWeight.w800 : FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLineChart(ThemeData theme) {
    if (_points.isEmpty) return const SizedBox.shrink();

    final maxVal = _points.map((p) => p.net).fold<int>(0, max);
    final safeMax = maxVal <= 0 ? 100000.0 : (maxVal * 1.35);
    final interval = (safeMax / 3).ceilToDouble();

    final spots = _points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.net.toDouble()))
        .toList(growable: false);

    final maxX = (_points.length - 1).toDouble();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMax,
        minX: 0,
        maxX: maxX < 0 ? 0 : maxX,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Color(0xFFE5E7EB),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (val, meta) {
                if (val <= 0 || val > safeMax + 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _wonAxis(val.round()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            if (!mounted) return;
            setState(() {
              if (response?.lineBarSpots != null &&
                  response!.lineBarSpots!.isNotEmpty) {
                _touchedIndex = response.lineBarSpots!.first.spotIndex;
              } else {
                _touchedIndex = -1;
              }
            });
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF7C3AED),
            tooltipRoundedRadius: 10,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                final idx = s.spotIndex;
                if (idx < 0 || idx >= _points.length) return null;
                final p = _points[idx];
                return LineTooltipItem(
                  '${p.label}\n${_won(p.net)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.4,
            color: const Color(0xFF7C3AED),
            barWidth: 3.5,
            isStrokeCapRound: true,
            shadow: const Shadow(
              color: Color(0x337C3AED),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) {
                final touched = idx == _touchedIndex;
                final isLast = idx == spots.length - 1;
                return FlDotCirclePainter(
                  radius: touched ? 8 : (isLast ? 6 : 4.5),
                  color: touched
                      ? const Color(0xFF7C3AED)
                      : (isLast ? const Color(0xFF7C3AED) : Colors.white),
                  strokeWidth: 2.5,
                  strokeColor: const Color(0xFF7C3AED),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF7C3AED).withOpacity(0.20),
                  const Color(0xFF7C3AED).withOpacity(0.05),
                  const Color(0xFF7C3AED).withOpacity(0.0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard() {
    return _InfoCard(children: [
      _InfoTile(
        icon: Icons.description_outlined,
        label: AppWords.terms,
        onTap: widget.onOpenTerms,
      ),
      const Divider(height: 1, indent: 52),
      _InfoTile(
        icon: Icons.privacy_tip_outlined,
        label: AppWords.privacy,
        onTap: widget.onOpenPrivacy,
      ),
    ]);
  }

  Widget _buildFaqSupportCard() {
    return _InfoCard(children: [
      _InfoTile(
        icon: Icons.support_agent_outlined,
        label: AppWords.support,
        onTap: widget.onOpenSupport,
      ),
    ]);
  }

  Widget _buildDangerZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEE2E2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoTile(
            icon: Icons.logout_rounded,
            label: AppWords.logout,
            iconColor: const Color(0xFFF43F5E),
            labelColor: const Color(0xFFF43F5E),
            onTap: _safeLogout,
          ),
          const Divider(height: 1, indent: 52),
          _InfoTile(
            icon: Icons.delete_forever_rounded,
            label: AppWords.deleteAccount,
            iconColor: const Color(0xFFF43F5E),
            labelColor: const Color(0xFFF43F5E),
            onTap: widget.onDeleteAccount,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ic = iconColor ?? const Color(0xFF6B7280);
    final lc = labelColor ?? const Color(0xFF111827);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ic),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: lc,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: ic.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }
}
