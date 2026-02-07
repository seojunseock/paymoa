// lib/screens/my_info_screen.dart
// ✅ 문구는 AppWords로 통일
// ✅ 그래프 로직/계산은 StatsRepository 그대로 사용

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../common/app_words.dart';
import '../data/stats_repository.dart';
import '../models/ui_calendar_models.dart';
import '../policies/policies.dart';

class MyInfoScreen extends StatefulWidget {
  const MyInfoScreen({
    super.key,
    required this.albas,
    required this.schedules,
    required this.wageAt,
    required this.taxOf,
    required this.insuranceOf,
    required this.policyOf,
    this.userAge,
    required this.payDay,
    this.onLogout,
    this.onDeleteAccount,
    this.onOpenTerms,
    this.onOpenPrivacy,
    this.onOpenFaq,
    this.onOpenSupport,
  });

  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final int Function(String albaId, DateTime dateLocal) wageAt;
  final TaxConfig? Function(String albaId) taxOf;
  final InsuranceConfig? Function(String albaId) insuranceOf;
  final SurchargePolicy? Function(String albaId) policyOf;

  final int? userAge;
  final int payDay;

  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenFaq;
  final VoidCallback? onOpenSupport;

  @override
  State<MyInfoScreen> createState() => _MyInfoScreenState();
}

class _MyInfoScreenState extends State<MyInfoScreen> {
  final StatsRepository _stats = const StatsRepository();

  int _monthlyGoal = 1000000;

  DateTime? _lastRefreshedAt =
      DateTime.now().subtract(const Duration(days: 10));

  List<MonthlyIncomePoint> _bars = const [];
  List<double> _line = const [];
  int? _age;

  @override
  void initState() {
    super.initState();
    _age = widget.userAge;
    _computeGraph();
  }

  @override
  void didUpdateWidget(covariant MyInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final paydayChanged = oldWidget.payDay != widget.payDay;
    final albasChanged = oldWidget.albas.length != widget.albas.length;
    final schedulesChanged =
        oldWidget.schedules.length != widget.schedules.length;

    if (albasChanged || schedulesChanged || paydayChanged) {
      _computeGraph();
    }
  }

  void _computeGraph() {
    final last4 = _stats.last4MonthsNet(
      albas: widget.albas,
      schedules: widget.schedules,
      wageAt: widget.wageAt,
      taxOf: (id) => widget.taxOf(id) ?? TaxConfig.none,
      insuranceOf: (id) => widget.insuranceOf(id) ?? const InsuranceNone(),
      policyOf: (id) => widget.policyOf(id) ?? const SurchargePolicy(),
    );

    final line = (_age == null)
        ? <double>[]
        : _stats.synthesizeCohortAverage(last4, ageSeed: _age);

    _bars = last4;
    _line = line;
    if (mounted) setState(() {});
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppWords.logout),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppWords.logoutDone)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppWords.logoutFailed}\n$e')),
      );
    }
  }

  bool _needRefreshForPayday(DateTime now, int payDay, DateTime? lastAt) {
    final payday = _safePaydayDate(now.year, now.month, payDay);
    if (now.isBefore(payday)) return false;
    if (lastAt == null) return true;
    return lastAt.isBefore(payday);
  }

  DateTime _safePaydayDate(int year, int month, int payDay) {
    final last = DateUtils.getDaysInMonth(year, month);
    final day = min(payDay, last);
    return DateTime(year, month, day);
  }

  void _handleRefresh() {
    _lastRefreshedAt = DateTime.now();
    _computeGraph();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppWords.refreshDone)),
    );
  }

  int get _currentMonthIncome => _bars.isNotEmpty ? _bars.last.amount : 0;

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _commaInt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  // ✅ MonthlyIncomePoint가 어떤 필드를 갖고 있든 "안 터지게" 라벨 만들기
  String _monthLabelSafe(MonthlyIncomePoint p) {
    final d = p as dynamic;

    int? y;
    int? m;

    try {
      y = d.year as int?;
    } catch (_) {}
    try {
      y ??= d.ymYear as int?;
    } catch (_) {}

    try {
      m = d.month as int?;
    } catch (_) {}
    try {
      m ??= d.ymMonth as int?;
    } catch (_) {}

    try {
      final DateTime dt = d.monthStart as DateTime;
      y ??= dt.year;
      m ??= dt.month;
    } catch (_) {}

    if (y != null && m != null) return '$m월';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final needRefresh =
        _needRefreshForPayday(now, widget.payDay, _lastRefreshedAt);

    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (needRefresh) _buildRefreshBanner(now),
            _buildGoalCard(),
            const SizedBox(height: 16),
            _buildGraphCard(),
            const SizedBox(height: 16),
            _buildPolicyCard(),
            const SizedBox(height: 16),
            _buildFaqSupportCard(),
            const SizedBox(height: 16),
            _buildDangerZoneCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshBanner(DateTime now) {
    final payday = _safePaydayDate(now.year, now.month, widget.payDay);
    return Card(
      color: Colors.amber.shade50,
      child: ListTile(
        leading: const Icon(Icons.update, color: Colors.orange),
        title: Text(
          AppWords.refreshNeededTitle,
          style: TextStyle(
            color: Colors.orange.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('${AppWords.payDayLabel}: ${_fmtDate(payday)}'),
        trailing: TextButton(
          onPressed: _handleRefresh,
          child: const Text(AppWords.refresh),
        ),
      ),
    );
  }

  Widget _buildGoalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이번 달 목표', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_commaInt(_monthlyGoal)}원',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final ctrl = TextEditingController(text: '$_monthlyGoal');
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('목표 금액 변경'),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(hintText: '예: 1000000'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text(AppWords.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(AppWords.ok),
                          ),
                        ],
                      ),
                    );

                    if (ok == true) {
                      final v = int.tryParse(ctrl.text.trim());
                      if (v != null && v >= 0) {
                        setState(() => _monthlyGoal = v);
                      }
                    }
                  },
                  child: const Text('변경'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '이번 달 현재: ${_commaInt(_currentMonthIncome)}원',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphCard() {
    final theme = Theme.of(context);

    if (_bars.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '표시할 데이터가 없어요.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final maxY =
        _bars.map((e) => e.amount).fold<int>(0, (p, c) => max(p, c)).toDouble();
    final safeMaxY = maxY <= 0 ? 1.0 : (maxY * 1.25);

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < _bars.length; i++) {
      final amt = _bars[i].amount.toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: amt,
              width: 18,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('최근 4개월 실수령', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: safeMaxY,
                  barGroups: groups,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= _bars.length)
                            return const SizedBox.shrink();
                          final label = _monthLabelSafe(_bars[i]);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label.isEmpty ? '${i + 1}' : label,
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      // ✅ tooltipBgColor는 네 버전에 없어서 제거
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final i = group.x.toInt();
                        final label = (i >= 0 && i < _bars.length)
                            ? _monthLabelSafe(_bars[i])
                            : '';
                        final v = rod.toY.round();
                        return BarTooltipItem(
                          '${label.isEmpty ? '' : '$label '}${_commaInt(v)}원',
                          theme.textTheme.bodySmall ?? const TextStyle(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (_line.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '※ 비슷한 나이 평균선은 현재 버전에선 숫자만 계산해두고, 화면 표시(선)는 다음 단계에서 추가할 수 있어요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text(AppWords.terms),
            onTap: widget.onOpenTerms,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text(AppWords.privacy),
            onTap: widget.onOpenPrivacy,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text(AppWords.openSourceLicense),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppWords.appName,
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSupportCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.help_center),
            title: const Text(AppWords.faq),
            onTap: widget.onOpenFaq,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text(AppWords.support),
            onTap: widget.onOpenSupport,
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    return Card(
      color: Colors.red.shade50,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade700),
            title: const Text(AppWords.logout),
            onTap: _safeLogout,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: const Text(AppWords.deleteAccount),
            onTap: widget.onDeleteAccount,
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
