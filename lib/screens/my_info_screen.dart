import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

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

  // 남기는 콜백: 약관/개인정보/FAQ/문의/로그아웃/탈퇴
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
  DateTime? _lastRefreshedAt = DateTime.now().subtract(const Duration(days: 10));

  List<MonthlyIncomePoint> _bars = const [];
  List<double> _line = const [];

  int? _age;

  @override
  void initState() {
    super.initState();
    _age = widget.userAge;
    _computeGraph();
  }

  // 부모에서 알바/스케줄/급여일이 바뀌면 즉시 재계산
  @override
  void didUpdateWidget(covariant MyInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final albasChanged = !identical(oldWidget.albas, widget.albas) ||
        oldWidget.albas.length != widget.albas.length;
    final schedulesChanged = !identical(oldWidget.schedules, widget.schedules) ||
        oldWidget.schedules.length != widget.schedules.length;
    final paydayChanged = oldWidget.payDay != widget.payDay;

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
    final line = (_age == null) ? <double>[] : _stats.synthesizeCohortAverage(last4, ageSeed: _age);
    _bars = last4;
    _line = line;
    if (mounted) setState(() {});
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
      const SnackBar(content: Text('이번 달 데이터로 갱신했습니다.')),
    );
  }

  int get _currentMonthIncome => _bars.isNotEmpty ? _bars.last.amount : 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final needRefresh = _needRefreshForPayday(now, widget.payDay, _lastRefreshedAt);

    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (needRefresh) _buildRefreshBanner(now),
            // 🔼 1) 목표 카드가 최상단
            _buildGoalCard(),
            const SizedBox(height: 16),
            // 🔽 2) 그래프 카드
            _buildGraphCard(),
            const SizedBox(height: 16),
            // 3) 정책(약관/개인정보/오픈소스)
            _buildPolicyCard(),
            const SizedBox(height: 16),
            // 4) FAQ & 고객센터
            _buildFaqSupportCard(),
            const SizedBox(height: 16),
            // 5) 위험영역: 로그아웃/회원탈퇴
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
          '급여일 기준 갱신 필요',
          style: TextStyle(
            color: Colors.orange.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('이번 달 급여일 (${_fmtDate(payday)}) 이후 새 데이터가 있어요.'),
        trailing: TextButton(
          onPressed: _handleRefresh,
          child: const Text('지금 갱신'),
        ),
      ),
    );
  }

  Widget _buildGraphCard() {
    final labels = _bars.map((e) => '${e.month.month}월').toList();
    final barValues = _bars.map((e) => e.amount.toDouble()).toList();
    final lineValues = _line;

    double maxY = 0;
    for (final v in barValues) {
      if (v > maxY) maxY = v;
    }
    for (final v in lineValues) {
      if (v > maxY) maxY = v;
    }
    maxY = maxY <= 0 ? 1000 : maxY * 1.15;

    final groups = List<BarChartGroupData>.generate(barValues.length, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: barValues[i],
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            color: Colors.green,
          ),
        ],
      );
    });

    final spots = List<FlSpot>.generate(
      lineValues.length,
      (i) => FlSpot(i.toDouble(), lineValues[i]),
    );

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  const Text(
                    '수입 그래프',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_age == null)
                    TextButton.icon(
                      onPressed: () async {
                        final v = await _openAgeDialog(context, _age);
                        if (v != null) {
                          setState(() => _age = v);
                          _computeGraph();
                        }
                      },
                      icon: const Icon(Icons.person),
                      label: const Text('나이 설정'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () async {
                        final v = await _openAgeDialog(context, _age);
                        if (v != null) {
                          setState(() => _age = v);
                          _computeGraph();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: Text('나이: $_age'),
                    ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 1.6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BarChart(
                    BarChartData(
                      maxY: maxY,
                      barGroups: groups,
                      gridData: FlGridData(show: true, drawHorizontalLine: true),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) => Text(
                              _fmtMoneyTick(value),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
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
                              if (i < 0 || i >= labels.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(labels[i], style: const TextStyle(fontSize: 12)),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (spots.isNotEmpty)
                    LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (barValues.length - 1).toDouble(),
                        minY: 0,
                        maxY: maxY,
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            barWidth: 2.5,
                            color: Colors.blue,
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_age != null)
              Row(
                children: [
                  _legendDot(Colors.blue),
                  const SizedBox(width: 6),
                  const Text('내 나이 때 월급 평균'),
                  const SizedBox(width: 16),
                  _legendDot(Colors.green),
                  const SizedBox(width: 6),
                  const Text('나의 월 수입'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ✅ 제목을 '목표'로 짧게, 설명 제거
  // ✅ '현재/목표' 라인에서 '목표' 금액을 탭하면 금액 설정 다이얼로그 오픈
  Widget _buildGoalCard() {
    final progress = _monthlyGoal <= 0 ? 0.0 : (_currentMonthIncome / _monthlyGoal).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('목표', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: LinearProgressIndicator(value: progress)),
                const SizedBox(width: 12),
                Text('${(progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '현재: ${_fmtMoney(_currentMonthIncome)} / '
                    '목표: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                // 목표 금액 부분만 따로 터치 가능 영역으로
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    final newGoal = await _openGoalDialog(context, _monthlyGoal);
                    if (newGoal != null) setState(() => _monthlyGoal = newGoal);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _fmtMoney(_monthlyGoal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
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
            title: const Text('서비스 이용약관'),
            onTap: widget.onOpenTerms,
            trailing: const Icon(Icons.chevron_right),
          ),
            const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('개인정보 처리방침'),
            onTap: widget.onOpenPrivacy,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('오픈소스 라이선스'),
            onTap: () {
              showLicensePage(context: context, applicationName: 'PayCount');
            },
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
            title: const Text('FAQ'),
            onTap: widget.onOpenFaq,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('고객센터 문의'),
            subtitle: const Text('이메일/카카오 채널/폼으로 문의'),
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
            title: const Text('로그아웃'),
            onTap: widget.onLogout,
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: const Text('회원탈퇴'),
            onTap: widget.onDeleteAccount,
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Future<int?> _openGoalDialog(BuildContext context, int initial) async {
    final controller = TextEditingController(text: initial.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('월 목표 금액 설정'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '숫자만 입력 (원)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('올바른 금액을 입력하세요.')),
                );
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<int?> _openAgeDialog(BuildContext context, int? initial) async {
    final controller = TextEditingController(text: initial?.toString() ?? '');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('나이 입력'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '예: 24',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 14 || v > 90) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('14~90 사이의 나이를 입력하세요.')),
                );
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    return result;
  }

  String _fmtMoney(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      buf.write(s[i]);
      final next = idx - 1;
      if (next > 0 && next % 3 == 0) buf.write(',');
    }
    return '${buf.toString()}원';
  }

  String _fmtMoneyTick(double value) {
    final v = value.round();
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}억';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}만';
    return v.toString();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}
