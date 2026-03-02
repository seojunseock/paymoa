// lib/ui/app_shell_owner.dart
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;

import '../auth/auth_service.dart';
import '../common/paymoa_design.dart';
import '../common/app_words.dart';
import '../data/firebase_service.dart';
import '../models/store.dart';
import '../models/store_worker.dart';
import '../screens/owner/owner_store_list_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/terms_screen.dart';
import '../common/support_dialog.dart';

const _primary = Pm.primary;
const _bg = Pm.bg;
const _textPrimary = Pm.textPrimary;
const _textSecondary = Pm.textSecondary;
const _textTertiary = Pm.textTertiary;

// ─────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────
class OwnerAppShell extends StatefulWidget {
  const OwnerAppShell({super.key});

  @override
  State<OwnerAppShell> createState() => _OwnerAppShellState();
}

class _OwnerAppShellState extends State<OwnerAppShell> {
  int _index = 0;

  Future<void> _logout() async {
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('로그아웃 실패: $e')));
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
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴하기',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;

    // ① 매장 + 하위 컬렉션 (workers, schedules) 삭제
    try {
      final storesSnap =
          await db.collection('users').doc(uid).collection('stores').get();
      for (final storeDoc in storesSnap.docs) {
        for (final sub in ['workers', 'schedules']) {
          await _deleteCollection(storeDoc.reference.collection(sub));
        }
        await storeDoc.reference.delete();
      }
      // ② users/{uid} 하위 기타 컬렉션 삭제
      for (final sub in ['myAlbas', 'storeJoins', 'schedules', 'policies']) {
        await _deleteCollection(db.collection('users').doc(uid).collection(sub));
      }
      await db.collection('users').doc(uid).delete();
    } catch (_) {
      // Firestore 삭제 실패 시에도 Auth 삭제는 진행
    }

    // ③ 카카오 연결 해제 (카카오로 로그인한 경우)
    try {
      await UserApi.instance.unlink();
    } catch (_) {
      // 카카오 로그인이 아닌 경우 무시
    }

    // ④ Firebase Auth 계정 삭제
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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('탈퇴 실패: $e')));
        }
      }
    }
  }

  /// Firestore 컬렉션 전체 삭제 (100건씩 배치)
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
        onOpenTerms: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TermsScreen()),
        ),
        onOpenPrivacy: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
        ),
        onOpenSupport: () => SupportDialog.show(context, isOwner: true),
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: _primary.withOpacity(0.10),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront_rounded, color: _primary),
            label: '매장',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded, color: _primary),
            label: '내 정보',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 사장님 내 정보 화면
// ─────────────────────────────────────────────
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
  List<_MonthPoint> _points = const [];
  bool _loading = true;
  int _touchedIndex = -1;

  StreamSubscription? _storesSub;

  @override
  void initState() {
    super.initState();
    _subscribeStores();
  }

  @override
  void dispose() {
    _storesSub?.cancel();
    super.dispose();
  }

  void _subscribeStores() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _storesSub = _repo.watchStores(uid).listen((stores) {
      _computeGraph(stores, uid);
    });
  }

  /// 3개월 총 인건비 계산
  Future<void> _computeGraph(List<Store> stores, String ownerUid) async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final totals = <int, int>{}; // month → total gross

      for (final store in stores) {
        // 매장별 근무자 + 스케줄 동시 조회
        final workers = await _repo
            .watchWorkers(
                ownerUid: ownerUid, storeId: store.id, activeOnly: false)
            .first;

        final Map<String, StoreWorker> workerMap = {
          for (final w in workers) w.workerUid: w,
        };

        // 최근 90일 스케줄
        final schedules = await _repo
            .watchRecentSchedulesForStore(
                ownerUid: ownerUid, storeId: store.id, recentDays: 95)
            .first;

        for (final s in schedules) {
          final start =
              DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
          var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          final workedMin = max(0,
              end.difference(start).inMinutes - s.breakMinutes.clamp(0, 1440));
          final schedDate = DateTime(s.year, s.month, s.day);
          final worker = workerMap[s.workerUid];
          final wage = worker != null
              ? worker.effectiveHourlyWageAt(store, schedDate)
              : (store.defaultHourlyWage ?? 0);
          final pay = (wage * workedMin / 60.0).round();

          totals[s.month] = (totals[s.month] ?? 0) + pay;
        }
      }

      // 최근 3개월 포인트 생성
      final pts = <_MonthPoint>[];
      for (int offset = 2; offset >= 0; offset--) {
        final dt = DateTime(now.year, now.month - offset, 1);
        pts.add(_MonthPoint(
            year: dt.year, month: dt.month, gross: totals[dt.month] ?? 0));
      }

      if (mounted) {
        setState(() {
          _points = pts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── helpers ─────────────────────────────────
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

  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          '내 정보',
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 20, color: _textPrimary),
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

  // ─── ① 3개월 인건비 꺾은선 카드 ─────────────
  Widget _buildLaborCostCard() {
    final hasData = _points.any((p) => p.gross > 0);

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
          // 헤더
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: _primary, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3개월 인건비',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: _textPrimary)),
                ],
              ),
              const Spacer(),
              if (!_loading && _points.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _won(_points.last.gross),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: _primary),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 24),

          // 그래프
          if (_loading)
            const SizedBox(
              height: 140,
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _primary)),
            )
          else if (!hasData)
            SizedBox(
              height: 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.show_chart_rounded,
                      size: 36, color: _textTertiary.withOpacity(0.4)),
                  const SizedBox(height: 8),
                  const Text('아직 근무 기록이 없어요',
                      style: TextStyle(color: _textTertiary)),
                ],
              ),
            )
          else
            SizedBox(height: 180, child: _buildLineChart()),

          // X축 레이블
          if (!_loading && hasData) ...[
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
                        '${p.month}월',
                        style: TextStyle(
                          fontSize: 15,
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
  }

  Widget _buildLineChart() {
    if (_points.isEmpty) return const SizedBox.shrink();
    final maxVal = _points.map((p) => p.gross).fold<int>(0, max);
    final safeMax = maxVal <= 0 ? 100000.0 : (maxVal * 1.35);
    final interval = (safeMax / 3).ceilToDouble();
    final spots = _points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.gross.toDouble()))
        .toList();

    return LineChart(LineChartData(
      minY: 0,
      maxY: safeMax,
      minX: 0,
      maxX: 2,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            interval: interval,
            getTitlesWidget: (val, meta) {
              if (val <= 0 || val > safeMax + 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(_wonAxis(val.round()),
                    style: const TextStyle(fontSize: 10, color: _textTertiary),
                    textAlign: TextAlign.right),
              );
            },
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchCallback: (event, response) {
          if (!mounted) return;
          setState(() {
            _touchedIndex = response?.lineBarSpots?.isNotEmpty == true
                ? response!.lineBarSpots!.first.spotIndex
                : -1;
          });
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _primary,
          tooltipRoundedRadius: 10,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.spotIndex;
            if (idx < 0 || idx >= _points.length) return null;
            final p = _points[idx];
            return LineTooltipItem(
              '${p.month}월\n${_won(p.gross)}',
              const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            );
          }).toList(),
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
                color: touched ? _primary : (isLast ? _primary : Colors.white),
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
    ));
  }

  // ─── ② 약관 카드 ─────────────────────────────
  Widget _buildPolicyCard() {
    return _InfoCard(children: [
      _InfoTile(
          icon: Icons.description_outlined,
          label: AppWords.terms,
          onTap: widget.onOpenTerms),
      const Divider(height: 1, indent: 52),
      _InfoTile(
          icon: Icons.privacy_tip_outlined,
          label: AppWords.privacy,
          onTap: widget.onOpenPrivacy),
      const Divider(height: 1, indent: 52),
      _InfoTile(
        icon: Icons.receipt_long_outlined,
        label: AppWords.openSourceLicense,
        onTap: () => showLicensePage(
            context: context, applicationName: AppWords.appName),
      ),
    ]);
  }

  // ─── ③ 문의하기 카드 ──────────────────────────
  Widget _buildFaqSupportCard() {
    return _InfoCard(children: [
      _InfoTile(
          icon: Icons.support_agent_outlined,
          label: AppWords.support,
          onTap: widget.onOpenSupport),
    ]);
  }

  // ─── ④ 위험 구역 카드 ────────────────────────
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
      child: Column(children: [
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
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 데이터 클래스
// ─────────────────────────────────────────────
class _MonthPoint {
  final int year;
  final int month;
  final int gross; // 세전 총 인건비

  const _MonthPoint(
      {required this.year, required this.month, required this.gross});
}

// ─────────────────────────────────────────────
// 공용 위젯
// ─────────────────────────────────────────────
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
              offset: const Offset(0, 4)),
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
            Icon(icon, size: 24, color: ic),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: lc)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 22, color: ic.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}
