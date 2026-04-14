// lib/ui/app_shell_owner.dart
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import '../ads/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;

import '../auth/auth_service.dart';
import '../common/paymoa_design.dart';
import '../common/app_words.dart';
import '../data/firebase_service.dart';
import '../screens/owner/owner_store_list_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/terms_screen.dart';
import '../common/support_dialog.dart';
import '../role/role_repository.dart';
import '../role/consent_repository.dart';
import '../screens/subscription_screen.dart';
import '../subscription/subscription_service.dart';

const _primary = Pm.primary;
const _bg = Pm.bg;
const _textPrimary = Pm.textPrimary;
const _textSecondary = Pm.textSecondary;
const _textTertiary = Pm.textTertiary;

class OwnerAppShell extends StatefulWidget {
  const OwnerAppShell({super.key});

  @override
  State<OwnerAppShell> createState() => _OwnerAppShellState();
}

class _OwnerAppShellState extends State<OwnerAppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _initSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdService.instance.requestShowWhenReady();
    });
  }

  Future<void> _initSubscription() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await SubscriptionService.instance.init(uid);
    if (!mounted) return;
    if (SubscriptionService.instance.shouldShowBillingWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBillingWarningDialog();
      });
    }
  }

  void _showBillingWarningDialog() {
    final info = SubscriptionService.instance.cached;
    if (info == null) return;

    final isExpired = info.status == SubscriptionStatus.expired;
    final daysLeft = info.remainingGraceDays;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: isExpired
                  ? const Color(0xFFF43F5E)
                  : const Color(0xFFF59E0B),
              size: 24,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '구독 결제에 문제가 생겼어요',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          isExpired
              ? '유예기간이 종료되어 무료 플랜으로 변경되었어요.\n'
                  '무료 한도를 초과한 매장·알바생 정보는\n읽기 전용으로 유지돼요.'
              : '결제를 확인해 주세요.\n'
                  '유예기간이 $daysLeft일 남았어요.\n'
                  '유예기간 중에는 모든 기능이 정상 제공돼요.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          if (!isExpired)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                SubscriptionSheet.show(context,
                    currentTier: SubscriptionService.instance.cached?.tier ??
                        PlanTier.free);
              },
              child: const Text(
                '구독 관리',
                style: TextStyle(color: Color(0xFF7C3AED)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    SubscriptionService.instance.clearSession();
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, '로그아웃에 실패했어요.\n잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('정말 탈퇴하시겠어요?'),
        content: const Text(
          '탈퇴하면 등록된 매장, 알바생 정보, 근무 기록이\n완전히 삭제되며 복구할 수 없어요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '탈퇴하기',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFF43F5E),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final roleRepo = RoleRepository();
    final consentRepo = ConsentRepository();

    try {
      final storesSnap =
          await db.collection('users').doc(uid).collection('stores').get();
      for (final storeDoc in storesSnap.docs) {
        for (final sub in ['workers', 'schedules']) {
          await _deleteCollection(storeDoc.reference.collection(sub));
        }
        await storeDoc.reference.delete();
      }

      for (final sub in ['myAlbas', 'storeJoins', 'schedules', 'policies']) {
        await _deleteCollection(
          db.collection('users').doc(uid).collection(sub),
        );
      }
      await db.collection('users').doc(uid).delete();
    } catch (_) {}

    try {
      await UserApi.instance.unlink();
    } catch (_) {}

    await roleRepo.clearRole(uid);
    await consentRepo.clearConsent(uid);

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('보안을 위해 로그아웃 후 다시 로그인하고 탈퇴해 주세요.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          showErrorDialog(context, '탈퇴에 실패했어요.\n잠시 후 다시 시도해 주세요.');
        }
      }
    }
  }

  Future<void> _deleteCollection(CollectionReference col) async {
    const batchSize = 100;
    while (true) {
      final snap = await col.limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = col.firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const OwnerStoreListScreen(),
      OwnerMyInfoScreen(
        onLogout: _logout,
        onDeleteAccount: _deleteAccount,
        onOpenTerms: () => launchUrl(
          Uri.parse('https://funky-mandevilla-5dc.notion.site/Terms-of-Service-9a7d10d5a0394f2a9cee324fe89893a7'),
          mode: LaunchMode.externalApplication,
        ),
        onOpenPrivacy: () => launchUrl(
          Uri.parse('https://funky-mandevilla-5dc.notion.site/Privacy-Policy-599f1871c09d40d782e5c1936444f6ac'),
          mode: LaunchMode.externalApplication,
        ),
        onOpenSupport: () => SupportDialog.show(context, isOwner: true),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AdBannerWidget(),
            Expanded(child: pages[_index]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: _primary.withOpacity(0.10),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded, color: _primary),
            label: '매장',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded, color: _primary),
            label: '내 정보',
          ),
        ],
      ),
    );
  }
}

class OwnerMyInfoScreen extends StatefulWidget {
  const OwnerMyInfoScreen({
    super.key,
    this.onLogout,
    this.onDeleteAccount,
    this.onOpenTerms,
    this.onOpenPrivacy,
    this.onOpenSupport,
  });

  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenSupport;

  @override
  State<OwnerMyInfoScreen> createState() => _OwnerMyInfoScreenState();
}

class _OwnerMyInfoScreenState extends State<OwnerMyInfoScreen> {
  final _repo = FirebaseService();
  int _touchedIndex = -1;
  Future<int>? _workerCountFuture;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _workerCountFuture = _fetchTotalWorkerCount(uid);
    }
  }

  Future<int> _fetchTotalWorkerCount(String uid) async {
    final db = FirebaseFirestore.instance;
    final stores =
        await db.collection('users').doc(uid).collection('stores').get();
    int total = 0;
    for (final s in stores.docs) {
      final workers = await s.reference.collection('workers').get();
      total += workers.size;
    }
    return total;
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
    if (n < 10000) return _comma(n);
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

  List<_MonthPoint> _normalizePoints(List<Map<String, dynamic>> raw) {
    final now = DateTime.now();
    final map = <String, int>{};

    for (final item in raw) {
      final year = (item['year'] as num?)?.toInt() ?? 0;
      final month = (item['month'] as num?)?.toInt() ?? 0;
      final gross = (item['gross'] as num?)?.toInt() ?? 0;
      if (year <= 0 || month <= 0) continue;
      map['$year-$month'] = gross;
    }

    final out = <_MonthPoint>[];
    for (int offset = 2; offset >= 0; offset--) {
      final dt = DateTime(now.year, now.month - offset, 1);
      final key = '${dt.year}-${dt.month}';
      out.add(
        _MonthPoint(
          year: dt.year,
          month: dt.month,
          gross: map[key] ?? 0,
        ),
      );
    }
    return out;
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
            color: _textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildLaborCostCard(),
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

  Widget _buildLaborCostCard() {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: uid.isEmpty
          ? const Stream<List<Map<String, dynamic>>>.empty()
          : _repo.watchOwnerMonthlyGrossPoints(ownerUid: uid, months: 3),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final points = _normalizePoints(
          snapshot.data ?? const <Map<String, dynamic>>[],
        );
        final hasData = points.any((p) => p.gross > 0);

        if (_touchedIndex >= points.length && _touchedIndex != -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _touchedIndex = -1);
          });
        }

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
                      color: _primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3개월 인건비',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        '최근 3개월 급여대장 기준 합계',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!loading && points.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '이번 달',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _textTertiary,
                          ),
                        ),
                        Text(
                          _won(points.last.gross),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (loading)
                const SizedBox(
                  height: 140,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primary,
                    ),
                  ),
                )
              else if (!hasData)
                SizedBox(
                  height: 140,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.show_chart_rounded,
                        size: 36,
                        color: _textTertiary.withOpacity(0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '아직 표시할 인건비가 없어요',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 180,
                  child: _buildLineChart(theme, points),
                ),
              if (!loading && hasData) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 44),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: points.map((p) {
                          final isLast = p == points.last;
                          return Text(
                            '${p.month}월',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isLast ? _primary : _textSecondary,
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
      },
    );
  }

  Widget _buildLineChart(ThemeData theme, List<_MonthPoint> points) {
    if (points.isEmpty) return const SizedBox.shrink();

    final maxVal = points.map((p) => p.gross).fold<int>(0, max);
    final safeMax = maxVal <= 0 ? 100000.0 : (maxVal * 1.35);
    final interval = (safeMax / 3).ceilToDouble();

    final spots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.gross.toDouble()))
        .toList(growable: false);

    final maxX = (points.length - 1).toDouble();

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
                      color: _textTertiary,
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
            getTooltipColor: (_) => _primary,
            tooltipRoundedRadius: 10,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                final idx = s.spotIndex;
                if (idx < 0 || idx >= points.length) return null;
                final p = points[idx];
                return LineTooltipItem(
                  '${p.month}월\n${_won(p.gross)}',
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
            color: _primary,
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
                  color:
                      touched ? _primary : (isLast ? _primary : Colors.white),
                  strokeWidth: 2.5,
                  strokeColor: _primary,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _primary.withOpacity(0.20),
                  _primary.withOpacity(0.05),
                  _primary.withOpacity(0.0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSubscription() {
    final tier = SubscriptionService.instance.cached?.tier ?? PlanTier.free;
    SubscriptionSheet.show(context, currentTier: tier);
  }

  Widget _buildPolicyCard() {
    return _InfoCard(children: [
      if (kSubscriptionVisible) ...[
        _InfoTile(
          icon: Icons.workspace_premium_rounded,
          label: '구독 플랜',
          onTap: _openSubscription,
        ),
        const Divider(height: 1, indent: 52),
      ],
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
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
            onTap: widget.onLogout,
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

class _MonthPoint {
  final int year;
  final int month;
  final int gross;

  const _MonthPoint({
    required this.year,
    required this.month,
    required this.gross,
  });
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
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
    final ic = iconColor ?? _textSecondary;
    final lc = labelColor ?? _textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ic),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: lc,
                    ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: ic.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }
}
