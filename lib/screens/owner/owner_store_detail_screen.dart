// lib/screens/owner/owner_store_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../export/export_service.dart';
import '../../export/payroll_excel_service.dart';
import '../../navigation/app_nav.dart';

import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../models/store_schedule.dart';

import '../../common/ui/async_state_views.dart';

import '../../data/firebase_service.dart';

import '../../policies/policies.dart';
import '../../policies/policy_mapper.dart' as pm;

import '../../payroll/payroll_engine.dart';
import '../../ads/ad_service.dart';
import '../../payroll/payroll_policy.dart';
import '../../payroll/payroll_document_service.dart';

import '../../models/ui_calendar_models.dart';
import '../subscription_screen.dart';
import '../../subscription/subscription_service.dart';

class OwnerStoreDetailScreen extends StatefulWidget {
  const OwnerStoreDetailScreen({
    super.key,
    required this.store,
    this.isReadOnly = false,
  });

  final Store store;
  final bool isReadOnly;

  @override
  State<OwnerStoreDetailScreen> createState() => _OwnerStoreDetailScreenState();
}

class _OwnerStoreDetailScreenState extends State<OwnerStoreDetailScreen> {
  final _workerRepo = FirebaseService();
  final _scheduleRepo = FirebaseService();
  final _engine = const PayrollEngine();
  final _docService = const PayrollDocumentService();

  static const _export = ExportService();

  bool _didEnsureSort = false;

  final Map<String, _PayPairPreview> _payCache = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didEnsureSort) {
      _didEnsureSort = true;
      _workerRepo.ensureSortIndexIfMissing(
        ownerUid: widget.store.ownerUid,
        storeId: widget.store.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;

    final joinCode =
        (store.storeCode != null && store.storeCode!.trim().isNotEmpty)
            ? store.storeCode!.trim()
            : store.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF111827)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          store.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: StreamBuilder<List<StoreWorker>>(
        stream: _workerRepo.watchWorkers(
          ownerUid: store.ownerUid,
          storeId: store.id,
          activeOnly: false,
        ),
        builder: (context, wSnap) {
          if (wSnap.connectionState == ConnectionState.waiting) {
            return const AppLoadingView();
          }
          if (wSnap.hasError) {
            return AppErrorView(
              title: '알바생 목록을 불러오지 못했어요.',
              message: '${wSnap.error}',
              onRetry: () => (context as Element).markNeedsBuild(),
            );
          }

          final allWorkersRaw = (wSnap.data ?? const <StoreWorker>[]);

          // ✅ status == deleted 는 화면에서 숨김(2차 내보내기)
          final allWorkers =
              allWorkersRaw.where((w) => w.status != 'deleted').toList();

          final activeWorkers =
              allWorkers.where((w) => w.isActive).toList(growable: false);

          final endedWorkers =
              allWorkers.where((w) => !w.isActive).toList(growable: false);

          return StreamBuilder<List<StoreSchedule>>(
            stream: _scheduleRepo.watchRecentSchedulesForStore(
              ownerUid: store.ownerUid,
              storeId: store.id,
            ),
            builder: (context, sSnap) {
              if (sSnap.connectionState == ConnectionState.waiting) {
                return const AppLoadingView();
              }
              if (sSnap.hasError) {
                return AppErrorView(
                  title: '근무 기록을 불러오지 못했어요.',
                  message: '${sSnap.error}',
                  onRetry: () => (context as Element).markNeedsBuild(),
                );
              }

              final schedulesRecent = sSnap.data ?? const <StoreSchedule>[];

              final Map<String, List<StoreSchedule>> byWorker = {};
              for (final s in schedulesRecent) {
                (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
              }

              final alive = allWorkers.map((w) => w.workerUid).toSet();
              _payCache.removeWhere((k, _) => !alive.contains(k));

              // ── 구독 플랜 알바생 한도 계산 ──────────────────
              final subInfo = SubscriptionService.instance.cached;
              final isExpiredPlan = kSubscriptionEnabled &&
                  subInfo?.status == SubscriptionStatus.expired;
              final storeIsReadOnly = widget.isReadOnly;
              // kSubscriptionVisible = true 시 플랜 한도 적용 (유예기간은 제한 없음)
              final isGracePlan = subInfo?.status == SubscriptionStatus.gracePeriod;
              final workerLimit = (kSubscriptionEnabled && kSubscriptionVisible && !isGracePlan)
                  ? (subInfo?.plan.maxWorkers ?? 999)
                  : 999;
              // ────────────────────────────────────────────────

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // ── 구독 배너 ──────────────────────────
                  if (isExpiredPlan || storeIsReadOnly) ...[
                    _WorkerBanner(
                      message: '구독이 만료됐어요. 일부 기능이 제한됩니다.',
                      color: const Color(0xFFFEE2E2),
                      textColor: const Color(0xFFF43F5E),
                      onUpgrade: () => SubscriptionSheet.show(context,
                          currentTier: SubscriptionService.instance.cached?.tier ?? PlanTier.free),
                    ),
                  ] else if (kSubscriptionEnabled && kSubscriptionVisible && activeWorkers.length > workerLimit) ...[
                    _WorkerBanner(
                      message: '플랜 한도에 도달했어요. 업그레이드하면 더 많은 알바생을 관리할 수 있어요.',
                      color: const Color(0xFFF3EEFF),
                      textColor: const Color(0xFF7C3AED),
                      onUpgrade: () => SubscriptionSheet.show(context,
                          currentTier: SubscriptionService.instance.cached?.tier ?? PlanTier.free),
                    ),
                  ],
                  // ── 초대 코드 한 줄 ──
                  _CodeRow(
                    code: joinCode,
                    onCopy: () {
                      _export.copyCsvToClipboard(
                          context: context,
                          csv: joinCode,
                          successMessage: '초대 코드가 복사됐어요.');
                    },
                  ),

                  const SizedBox(height: 10),

                  // ── 문서 받기 ──
                  _DocRow(
                    payDay: store.payDay ?? 15,
                    onPickDate: () => _pickYearMonthWheel(context),
                    onExport: (type, year, month) async {
                      // 잠긴 알바생 제외: 활성 한도 내 인원 + 내보낸 알바생
                      final exportWorkers = (isExpiredPlan &&
                              activeWorkers.length > workerLimit)
                          ? [
                              ...activeWorkers.sublist(0, workerLimit),
                              ...endedWorkers,
                            ]
                          : allWorkers;

                      void doExport() => _exportDoc(
                            store: store,
                            workers: exportWorkers,
                            docType: type,
                            year: year,
                            month: month,
                          );

                      if (!kSubscriptionEnabled) {
                        // 구독 비활성화: 광고 없이 바로 받기
                        doExport();
                      } else {
                        final tier =
                            SubscriptionService.instance.cached?.tier;
                        final isPaid = tier != null &&
                            tier != PlanTier.free;
                        if (isPaid) {
                          // 유료 플랜: 광고 없이 바로 받기
                          doExport();
                        } else {
                          // 무료 플랜: 리워드 광고 시청 후 받기
                          AdService.instance.showRewardedAd(
                            onRewarded: () {
                              if (!context.mounted) return;
                              doExport();
                            },
                            onNotReady: doExport,
                          );
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  // ── 알바생
                  Row(
                    children: [
                      const Text('알바생',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827))),
                      const Spacer(),
                      Text('${activeWorkers.length}명',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7C3AED))),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (activeWorkers.isEmpty)
                    const AppEmptyView(
                      icon: Icons.people_alt_outlined,
                      title: '아직 알바생이 없어요.',
                      message: '알바생이 “매장 코드”로 참여하면 여기서 보입니다.',
                    )
                  else
                    ...activeWorkers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final w = entry.value;
                      final wsRaw =
                          byWorker[w.workerUid] ?? const <StoreSchedule>[];
                      final ws = [...wsRaw]..sort(_scheduleSort);

                      final payPair = _computePayPairCached(
                        store: store,
                        worker: w,
                        schedulesSorted: ws,
                      );

                      // 매장 잠금 또는 알바생 한도 초과 시 잠금
                      final isLocked =
                          storeIsReadOnly || (isExpiredPlan && idx >= workerLimit);

                      return Padding(
                        key: ValueKey('active_${w.workerUid}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _WorkerSimpleCard(
                          enabled: true,
                          isLocked: isLocked,
                          name: _displayName(w),
                          badge: _badgeText(worker: w),
                          wageText: '${_comma(payPair.effectiveWage)}원',
                          prevLabel: _payLabel(payPair.prev.payDate),
                          prevValue: '${_comma(payPair.prev.net)}원',
                          curLabel: _payLabel(payPair.cur.payDate),
                          curValue: '${_comma(payPair.cur.net)}원',
                          surcharge: payPair.surcharge,
                          onExport: () =>
                              _onExportWorker(store: store, worker: w),
                          onOpenCalendar: () => AppNav.openOwnerWorkerCalendar(
                            context,
                            store: store,
                            worker: w,
                          ),
                          onEdit: () => AppNav.openOwnerWorkerSettings(
                            context,
                            store: store,
                            worker: w,
                            workerSchedules: byWorker[w.workerUid] ?? const [],
                          ),
                        ),
                      );
                    }),

                  if (endedWorkers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _EndedSection(
                      title: '내보낸 알바생',
                      count: endedWorkers.length,
                      children: endedWorkers.map((w) {
                        final wsRaw =
                            byWorker[w.workerUid] ?? const <StoreSchedule>[];
                        // endedAt 이후 스케줄 제외
                        final endDate = w.endedAt;
                        final ws = [...wsRaw]
                          ..removeWhere((s) =>
                              endDate != null &&
                              DateTime(s.year, s.month, s.day).isAfter(DateTime(
                                  endDate.year, endDate.month, endDate.day)))
                          ..sort(_scheduleSort);

                        final payPair = _computePayPairCached(
                          store: store,
                          worker: w,
                          schedulesSorted: ws,
                        );

                        return Padding(
                          key: ValueKey('ended_${w.workerUid}'),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WorkerSimpleCard(
                            enabled: false,
                            name: _displayName(w),
                            badge: _badgeText(worker: w),
                            wageText: '${_comma(payPair.effectiveWage)}원',
                            prevLabel: _payLabel(payPair.prev.payDate),
                            prevValue: '${_comma(payPair.prev.net)}원',
                            curLabel: _payLabel(payPair.cur.payDate),
                            curValue: '${_comma(payPair.cur.net)}원',
                            surcharge: payPair.surcharge,
                            onExport: () =>
                                _onExportWorker(store: store, worker: w),
                            onOpenCalendar: () =>
                                AppNav.openOwnerWorkerCalendar(
                              context,
                              store: store,
                              worker: w,
                              endedAt: w.endedAt,
                            ),
                            onEdit: () => AppNav.openOwnerWorkerSettings(
                              context,
                              store: store,
                              worker: w,
                              workerSchedules:
                                  byWorker[w.workerUid] ?? const [],
                            ),
                            onDelete: () => _onDeleteWorkerCompletely(
                              store: store,
                              worker: w,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  // 이메일 입력 (간소화)
  Future<String?> _askEmail(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이메일 주소'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'example@gmail.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final email = controller.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('올바른 이메일을 입력해주세요')),
                );
                return;
              }
              Navigator.pop(ctx, email);
            },
            child: const Text('확인',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          ),
        ],
      ),
    );
    return result;
  }

  Future<_YearMonth?> _pickYearMonthWheel(BuildContext context) async {
    final now = DateTime.now();
    final defaultYear = now.year.clamp(2025, 2040);
    final defaultMonth = now.month;

    final years = List.generate(2040 - 2025 + 1, (i) => 2025 + i);
    final months = List.generate(12, (i) => i + 1);

    int yearIndex = years.indexOf(defaultYear);
    if (yearIndex < 0) yearIndex = 0;

    int monthIndex = defaultMonth - 1;
    monthIndex = monthIndex.clamp(0, 11);

    final yearController = FixedExtentScrollController(initialItem: yearIndex);
    final monthController =
        FixedExtentScrollController(initialItem: monthIndex);

    return showModalBottomSheet<_YearMonth>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        int selectedYear = years[yearIndex];
        int selectedMonth = months[monthIndex];

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return SizedBox(
                height: 320,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('취소'),
                          ),
                          const Spacer(),
                          Text(
                            '월 선택',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(
                              ctx,
                              _YearMonth(selectedYear, selectedMonth),
                            ),
                            child: const Text('선택',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: yearController,
                              itemExtent: 44,
                              onSelectedItemChanged: (i) =>
                                  setState(() => selectedYear = years[i]),
                              children: [
                                for (final y in years)
                                  Center(
                                      child: Text('$y년',
                                          style:
                                              const TextStyle(fontSize: 18))),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: monthController,
                              itemExtent: 44,
                              onSelectedItemChanged: (i) =>
                                  setState(() => selectedMonth = months[i]),
                              children: [
                                for (final m in months)
                                  Center(
                                      child: Text('$m월',
                                          style:
                                              const TextStyle(fontSize: 18))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _exportThisPeriodCsv({
    required BuildContext context,
    required Store store,
    required List<StoreWorker> workers,
  }) async {
    final basePolicy = store.payrollPolicy;
    final now = DateTime.now();
    final preview =
        computePreviewForDate(policy: basePolicy, anyDateInPeriod: now);
    final period = preview.period;

    await _withLoading(context, message: '급여대장 준비 중…', () async {
      final schedulesAll = await _scheduleRepo.fetchSchedulesForStoreInRange(
        ownerUid: store.ownerUid,
        storeId: store.id,
        startInclusive: period.start,
        endInclusive: period.end,
      );

      final rows = _docService.buildPeriodDocument(
        store: store,
        workers: workers,
        schedules: schedulesAll,
        period: period,
      );

      if (!context.mounted) return;
      await _copyRowsAsCsv(context: context, title: '급여대장', rows: rows);
    });
  }

  Future<void> _exportPrevPeriodCsv({
    required BuildContext context,
    required Store store,
    required List<StoreWorker> workers,
  }) async {
    final basePolicy = store.payrollPolicy;
    final now = DateTime.now();
    final thisPreview =
        computePreviewForDate(policy: basePolicy, anyDateInPeriod: now);
    final prevSeed = thisPreview.period.start.subtract(const Duration(days: 1));
    final prevPreview =
        computePreviewForDate(policy: basePolicy, anyDateInPeriod: prevSeed);
    final period = prevPreview.period;

    await _withLoading(context, message: '급여대장 준비 중…', () async {
      final schedulesAll = await _scheduleRepo.fetchSchedulesForStoreInRange(
        ownerUid: store.ownerUid,
        storeId: store.id,
        startInclusive: period.start,
        endInclusive: period.end,
      );

      final rows = _docService.buildPeriodDocument(
        store: store,
        workers: workers,
        schedules: schedulesAll,
        period: period,
      );

      if (!context.mounted) return;
      await _copyRowsAsCsv(context: context, title: '급여대장', rows: rows);
    });
  }

  Future<void> _exportMonthCsv({
    required BuildContext context,
    required Store store,
    required List<StoreWorker> workers,
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month, _daysInMonth(year, month));

    await _withLoading(context, message: '$year년 $month월 문서 준비 중…', () async {
      final schedulesAll = await _scheduleRepo.fetchSchedulesForStoreInRange(
        ownerUid: store.ownerUid,
        storeId: store.id,
        startInclusive: start,
        endInclusive: end,
      );

      final rows = _docService.buildCalendarMonthDocument(
        store: store,
        workers: workers,
        schedules: schedulesAll,
        year: year,
        month: month,
      );

      if (!context.mounted) return;
      await _copyRowsAsCsv(
          context: context, title: '급여대장 ${year}년 ${month}월', rows: rows);
    });
  }

  int _daysInMonth(int y, int m) {
    final firstNext = (m == 12) ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  Future<void> _withLoading(
    BuildContext context,
    Future<void> Function() task, {
    required String message,
  }) async {
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );

    try {
      await task();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _copyRowsAsCsv({
    required BuildContext context,
    required String title,
    required List<PayrollDocumentRow> rows,
  }) async {
    final csv = _rowsToCsv(rows);
    await _export.copyCsvToClipboard(
      context: context,
      csv: csv,
      successMessage: '$title · ${rows.length}명 복사됐어요.',
    );
  }

  String _rowsToCsv(List<PayrollDocumentRow> rows) {
    const header = [
      'kind',
      'storeName',
      'workerName',
      'periodStart',
      'periodEnd',
      'payDate',
      'hourlyWage',
      'scheduleCount',
      'workedTime',
      'gross',
      'net',
    ];

    String esc(Object? v) {
      final s = (v ?? '').toString();
      final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
      final q = s.replaceAll('"', '""');
      return needsQuote ? '"$q"' : q;
    }

    final lines = <String>[header.join(',')];
    for (final r in rows) {
      final m = r.toExcelMap();
      lines.add([
        esc(m['kind']),
        esc(m['storeName']),
        esc(m['workerName']),
        esc(m['periodStart']),
        esc(m['periodEnd']),
        esc(m['payDate']),
        esc(m['hourlyWage']),
        esc(m['scheduleCount']),
        esc(m['workedTime']),
        esc(m['gross']),
        esc(m['net']),
      ].join(','));
    }
    return lines.join('\n');
  }

  Future<void> _onExportWorker({
    required Store store,
    required StoreWorker worker,
  }) async {
    if (!worker.isActive) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('매장에서 내보낼까요?'),
        content: const Text('근무 기록과 급여 정보는 그대로 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('내보내기',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    await _workerRepo.exportWorkerStep(
      ownerUid: store.ownerUid,
      storeId: store.id,
      workerUid: worker.workerUid,
      step: 1,
    );
  }

  Future<void> _onDeleteWorkerCompletely({
    required Store store,
    required StoreWorker worker,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('완전 삭제할까요?'),
        content: const Text('모든 근무 기록과 정보가 영구적으로 삭제됩니다. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await _workerRepo.deleteWorkerCompletely(
      ownerUid: store.ownerUid,
      storeId: store.id,
      workerUid: worker.workerUid,
    );
  }

  _PayPairPreview _computePayPairCached({
    required Store store,
    required StoreWorker worker,
    required List<StoreSchedule> schedulesSorted,
  }) {
    final effectiveWage = _effectiveWage(store: store, worker: worker);
    final effectivePayDay = _effectivePayDay(store: store, worker: worker);

    final effectiveTax = _effectiveTax(store: store, worker: worker);
    final effectiveInsurance =
        _effectiveInsurance(store: store, worker: worker);
    final surcharge = _effectiveSurcharge(store: store, worker: worker);

    final basePolicy = store.payrollPolicy;
    final policy = basePolicy.copyWith(
      payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
    );

    final len = schedulesSorted.length;
    int lastUpdatedMs = 0;
    for (final s in schedulesSorted) {
      final ms = (s.updatedAt?.millisecondsSinceEpoch ?? 0);
      if (ms > lastUpdatedMs) lastUpdatedMs = ms;
    }
    final schKey = 'len:$len|u:$lastUpdatedMs';

    final taxKey = _taxKey(effectiveTax);
    final insKey = _insKey(effectiveInsurance);
    final surchargeKey = _surchargeKey(surcharge);
    final policyKey = _payrollPolicyKey(policy);

    final cacheKey =
        '${worker.workerUid}|w$effectiveWage|p$effectivePayDay|pp:$policyKey|t$taxKey|i$insKey|s$surchargeKey|$schKey';

    final cached = _payCache[worker.workerUid];
    if (cached != null && cached.cacheKey == cacheKey) return cached;

    final uiSchedules = schedulesSorted.map((s) {
      return UICalendarSchedule(
        id: s.id,
        albaId: s.workerUid,
        year: s.year,
        month: s.month,
        day: s.day,
        startHour: s.startHour,
        startMinute: s.startMinute,
        endHour: s.endHour,
        endMinute: s.endMinute,
        breakMinutes: s.breakMinutes,
        workType: _mapWorkType(s.workType),
        overrideHourlyWage: s.overrideHourlyWage,
      );
    }).toList(growable: false);

    final alba = UICalendarAlba(
      id: worker.workerUid,
      storeId: store.id,
      name: _displayName(worker),
      hourlyWage: effectiveWage,
      colorHex: 'FF000000',
      payDay: effectivePayDay,
    );

    final now = DateTime.now();
    final ph =
        worker.inheritFromStore ? store.policyHistory : worker.policyHistory;
    SurchargePolicy Function(DateTime)? surchargeAtFn;
    TaxConfig Function(DateTime)? taxAtFn;
    InsuranceConfig Function(DateTime)? insuranceAtFn;
    if (ph.isNotEmpty) {
      surchargeAtFn = (date) => ph.surchargeAt(date) ?? surcharge;
      taxAtFn = (date) => ph.taxAt(date) ?? effectiveTax;
      insuranceAtFn = (date) => ph.insuranceAt(date) ?? effectiveInsurance;
    }

    final wagePh =
        worker.inheritFromStore ? store.policyHistory : worker.policyHistory;
    int Function(String, DateTime)? wageAtFn;
    if (wagePh.isNotEmpty) {
      final wageEntries = wagePh.entries
          .where((e) => e.rawPolicy['hourlyWage'] != null)
          .toList()
        ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      if (wageEntries.isNotEmpty) {
        final bands = <({DateTime from, int wage})>[];
        final prevW = wageEntries.first.rawPolicy['previousHourlyWage'];
        if (prevW != null) {
          final pw = (prevW is int)
              ? prevW
              : (prevW is num)
                  ? prevW.toInt()
                  : int.tryParse('$prevW') ?? 0;
          if (pw > 0) bands.add((from: DateTime(1970), wage: pw));
        }
        for (final e in wageEntries) {
          final w = e.rawPolicy['hourlyWage'];
          final wage = (w is int)
              ? w
              : (w is num)
                  ? w.toInt()
                  : int.tryParse('$w') ?? 0;
          if (wage > 0) bands.add((from: e.effectiveFrom, wage: wage));
        }
        if (bands.isNotEmpty) {
          wageAtFn = (albaId, date) {
            final d0 = DateTime(date.year, date.month, date.day);
            int? last;
            for (final b in bands) {
              if (!b.from.isAfter(d0)) {
                last = b.wage;
              } else {
                break;
              }
            }
            return last ?? effectiveWage;
          };
        }
      }
    }

    final thisSummary = _engine.summaryForDate(
      policy: policy,
      alba: alba,
      schedules: uiSchedules,
      tax: effectiveTax,
      insurance: effectiveInsurance,
      surchargePolicy: surcharge,
      surchargeAt: surchargeAtFn,
      taxAt: taxAtFn,
      insuranceAt: insuranceAtFn,
      wageAt: wageAtFn,
      anyDateInPeriod: now,
    );

    final prevSeed = thisSummary.period.start.subtract(const Duration(days: 1));
    final prevSummary = _engine.summaryForDate(
      policy: policy,
      alba: alba,
      schedules: uiSchedules,
      tax: effectiveTax,
      insurance: effectiveInsurance,
      surchargePolicy: surcharge,
      surchargeAt: surchargeAtFn,
      taxAt: taxAtFn,
      insuranceAt: insuranceAtFn,
      wageAt: wageAtFn,
      anyDateInPeriod: prevSeed,
    );

    final out = _PayPairPreview(
      cacheKey: cacheKey,
      effectiveWage: effectiveWage,
      effectivePayDay: effectivePayDay,
      tax: effectiveTax,
      insurance: effectiveInsurance,
      surcharge: surcharge,
      prev: _PayOnePreview(
        payDate: prevSummary.payDate,
        gross: prevSummary.gross,
        net: prevSummary.net,
      ),
      cur: _PayOnePreview(
        payDate: thisSummary.payDate,
        gross: thisSummary.gross,
        net: thisSummary.net,
      ),
    );

    _payCache[worker.workerUid] = out;
    return out;
  }

  Future<void> _exportDoc({
    required Store store,
    required List<StoreWorker> workers,
    required _DocType docType,
    required int year,
    required int month,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final svc = PayrollExcelService();

      if (docType == _DocType.simplifiedStatement) {
        final halfYear = month <= 6 ? 1 : 2;
        final startM = halfYear == 1 ? 1 : 7;
        final endM = halfYear == 1 ? 6 : 12;

        final fetchStart =
            DateTime(year, startM, 1).subtract(const Duration(days: 62));
        final fetchEnd = DateTime(year, endM + 1, 0);

        final schedules = await _scheduleRepo.fetchSchedulesForStoreInRange(
          ownerUid: store.ownerUid,
          storeId: store.id,
          startInclusive: fetchStart,
          endInclusive: fetchEnd,
        );

        await svc.generateSimplifiedStatement(
          store: store,
          workers: workers,
          schedules: schedules,
          year: year,
          halfYear: halfYear,
        );
      } else {
        final monthStart = DateTime(year, month, 1);
        final monthEnd = DateTime(year, month + 1, 0);

        final fetchStart = monthStart.subtract(const Duration(days: 62));
        final fetchEnd = monthEnd;

        final schedules = await _scheduleRepo.fetchSchedulesForStoreInRange(
          ownerUid: store.ownerUid,
          storeId: store.id,
          startInclusive: fetchStart,
          endInclusive: fetchEnd,
        );

        if (docType == _DocType.wageStatement) {
          await svc.generateWageStatements(
            store: store,
            workers: workers,
            schedules: schedules,
            year: year,
            month: month,
          );
        } else {
          await svc.generatePayrollLedger(
            store: store,
            workers: workers,
            schedules: schedules,
            year: year,
            month: month,
          );
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('문서를 공유했습니다!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('오류가 발생했어요. 잠시 후 다시 시도해 주세요.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

class _YearMonth {
  final int year;
  final int month;
  const _YearMonth(this.year, this.month);
}

class _PayOnePreview {
  final DateTime payDate;
  final int gross;
  final int net;
  const _PayOnePreview({
    required this.payDate,
    required this.gross,
    required this.net,
  });
}

class _PayPairPreview {
  final String cacheKey;

  final int effectiveWage;
  final int effectivePayDay;

  final TaxConfig tax;
  final InsuranceConfig insurance;
  final SurchargePolicy surcharge;

  final _PayOnePreview prev;
  final _PayOnePreview cur;

  const _PayPairPreview({
    required this.cacheKey,
    required this.effectiveWage,
    required this.effectivePayDay,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.prev,
    required this.cur,
  });
}

int _effectiveWage({required Store store, required StoreWorker worker}) {
  final int? storeWage = store.defaultHourlyWage;
  return worker.inheritFromStore
      ? (storeWage ?? worker.hourlyWage ?? 0)
      : (worker.hourlyWage ?? storeWage ?? 0);
}

int _effectivePayDay({required Store store, required StoreWorker worker}) {
  final int? storePayDay = store.payDay;
  final resolved = worker.inheritFromStore
      ? (storePayDay ?? worker.payDay ?? 15)
      : (worker.payDay ?? storePayDay ?? 15);
  return resolved.clamp(1, 31);
}

TaxConfig _effectiveTax({required Store store, required StoreWorker worker}) {
  final base = store.taxConfig;
  final o = worker.policyOverride;
  if (o == null) return base;
  final rawTax = o['tax'];
  if (rawTax == null) return base;
  return pm.taxConfigFromAny(rawTax);
}

InsuranceConfig _effectiveInsurance({
  required Store store,
  required StoreWorker worker,
}) {
  final base = store.insuranceConfig;
  final o = worker.policyOverride;
  if (o == null) return base;
  final raw = o['insurance'];
  if (raw == null) return base;
  return pm.insuranceConfigFromAny(raw);
}

SurchargePolicy _effectiveSurcharge({
  required Store store,
  required StoreWorker worker,
}) {
  if (worker.inheritFromStore) return store.surchargePolicy;
  final root = worker.policyOverride ?? const <String, dynamic>{};
  return pm.surchargePolicyFromAny(root['surcharge']);
}

WorkType _mapWorkType(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'substitute':
      return WorkType.substitute;
    case 'night':
      return WorkType.night;
    case 'overtime':
      return WorkType.overtime;
    case 'holiday':
      return WorkType.holiday;
    default:
      return WorkType.basic;
  }
}

int _scheduleSort(StoreSchedule a, StoreSchedule b) {
  final ak = a.year * 10000 + a.month * 100 + a.day;
  final bk = b.year * 10000 + b.month * 100 + b.day;
  if (ak != bk) return ak.compareTo(bk);
  final am = a.startHour * 60 + a.startMinute;
  final bm = b.startHour * 60 + b.startMinute;
  return am.compareTo(bm);
}

String _displayName(StoreWorker w) {
  final dn = (w.displayName ?? '').trim();
  return dn.isEmpty ? w.workerUid : dn;
}

String _payLabel(DateTime payDate) => '${payDate.month}/${payDate.day}';
String _badgeText({required StoreWorker worker}) =>
    worker.inheritFromStore ? '기본' : '개인';

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code, required this.onCopy});
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.05),
              blurRadius: 0,
              spreadRadius: 1),
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(children: [
        const Icon(Icons.qr_code_rounded, size: 20, color: Color(0xFF7C3AED)),
        const SizedBox(width: 10),
        const Text('초대 코드',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280))),
        const SizedBox(width: 10),
        Expanded(
            child: Text(code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827)))),
        GestureDetector(
          onTap: onCopy,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('복사',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C3AED))),
          ),
        ),
      ]),
    );
  }
}

enum _DocType {
  wageStatement,
  payrollLedger,
  simplifiedStatement,
}

extension _DocTypeLabel on _DocType {
  String get label {
    switch (this) {
      case _DocType.wageStatement:
        return '임금명세서';
      case _DocType.payrollLedger:
        return '급여대장';
      case _DocType.simplifiedStatement:
        return '간이지급명세서';
    }
  }
}

class _DocRow extends StatefulWidget {
  const _DocRow({
    required this.payDay,
    required this.onPickDate,
    required this.onExport,
  });

  final int payDay;
  final Future<_YearMonth?> Function() onPickDate;
  final Future<void> Function(_DocType type, int year, int month) onExport;

  @override
  State<_DocRow> createState() => _DocRowState();
}

class _DocRowState extends State<_DocRow> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  _DocType _docType = _DocType.wageStatement;

  Future<void> _pickDate() async {
    final picked = await widget.onPickDate();
    if (picked == null) return;
    setState(() {
      _year = picked.year;
      _month = picked.month;
    });
  }

  int _displayPayDay() {
    final lastDay = DateTime(_year, _month + 1, 0).day;
    return widget.payDay.clamp(1, lastDay);
  }

  @override
  Widget build(BuildContext context) {
    final payDay = _displayPayDay();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EEFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 17, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 8),
                  Text(
                    '$_year년 $_month월 · $payDay일 급여일',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3B0764),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.expand_more,
                      size: 18, color: Color(0xFF7C3AED)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final t in _DocType.values) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _docType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _docType == t
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFFF3EEFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _docType == t
                              ? Colors.white
                              : const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ),
                ),
                if (t != _DocType.simplifiedStatement) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => widget.onExport(_docType, _year, _month),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '문서받기',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndedSection extends StatefulWidget {
  const _EndedSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  State<_EndedSection> createState() => _EndedSectionState();
}

class _EndedSectionState extends State<_EndedSection> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Text('${widget.title} (${widget.count}명)',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
                const Spacer(),
                Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: const Color(0xFF9CA3AF)),
              ]),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
              child: Column(children: widget.children),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkerSimpleCard extends StatefulWidget {
  const _WorkerSimpleCard({
    required this.enabled,
    required this.name,
    required this.badge,
    required this.wageText,
    required this.prevLabel,
    required this.prevValue,
    required this.curLabel,
    required this.curValue,
    required this.surcharge,
    required this.onExport,
    required this.onOpenCalendar,
    required this.onEdit,
    this.onDelete,
    this.isLocked = false,
  });

  final bool enabled;
  final bool isLocked;
  final String name;
  final String badge;
  final String wageText;
  final String prevLabel;
  final String prevValue;
  final String curLabel;
  final String curValue;
  final SurchargePolicy surcharge;
  final VoidCallback onExport;
  final VoidCallback onOpenCalendar;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  State<_WorkerSimpleCard> createState() => _WorkerSimpleCardState();
}

class _WorkerSimpleCardState extends State<_WorkerSimpleCard> {
  bool _expanded = false;
  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    // 잠금 상태: 흐리게 + 자물쇠 아이콘 + 탭 시 구독 시트
    if (widget.isLocked) {
      return Opacity(
        opacity: 0.4,
        child: GestureDetector(
          onTap: () => SubscriptionSheet.show(context,
                currentTier: SubscriptionService.instance.cached?.tier ??
                    PlanTier.free),
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(16)),
                border: Border.all(color: const Color(0xFFF3F4F6)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '시급 ${widget.wageText}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_rounded,
                      size: 18, color: Color(0xFF9CA3AF)),
                ],
              ),
            ),
            // 컬러 바 (보라색)
            Positioned(
              left: 0,
              top: 7,
              bottom: 7,
              child: Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    final opacity = widget.enabled ? 1.0 : 0.5;
    final sur = widget.surcharge;
    final surchargeItems = <String>[];
    if (sur.nightEnabled) surchargeItems.add('야간 +${sur.nightPercent}%');
    if (sur.overtimeEnabled) surchargeItems.add('연장 +${sur.overtimePercent}%');
    if (sur.holidayEnabled) surchargeItems.add('휴일 +${sur.holidayPercent}%');
    if (sur.weeklyHolidayEnabled) surchargeItems.add('주휴수당');

    return Opacity(
      opacity: opacity,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(16)),
            border: Border.all(color: const Color(0xFFF3F4F6)),
            boxShadow: [
              BoxShadow(
                  color: _purple.withOpacity(0.05),
                  blurRadius: 0,
                  spreadRadius: 1),
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 14, 14),
              iconColor: _purple,
              collapsedIconColor: const Color(0xFF9CA3AF),
              onExpansionChanged: (v) => setState(() => _expanded = v),
              title: Row(children: [
                Expanded(
                  child: Text(widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(widget.badge,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _purple)),
                ),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('시급 ${widget.wageText}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 6),
                    _PayBadge(
                        label: '저번 ${widget.prevLabel}',
                        value: widget.prevValue),
                    const SizedBox(height: 4),
                    _PayBadge(
                        label: '이번 ${widget.curLabel}',
                        value: widget.curValue,
                        highlight: true),
                  ],
                ),
              ),
              children: [
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 12),
                if (surchargeItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: surchargeItems
                        .map((label) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _purple.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(label,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _purple)),
                            ))
                        .toList(),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  const Text('가산정책 없음',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: widget.enabled
                          ? Row(children: [
                          Expanded(
                              child: TextButton.icon(
                            onPressed: widget.onExport,
                            icon: const Icon(Icons.person_remove_outlined,
                                size: 16, color: Color(0xFFF43F5E)),
                            label: const Text('내보내기',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF43F5E))),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                          )),
                          Container(
                              width: 1,
                              height: 22,
                              color: const Color(0xFFE5E7EB)),
                          Expanded(
                              child: TextButton.icon(
                            onPressed: widget.onOpenCalendar,
                            icon: const Icon(Icons.calendar_today_outlined,
                                size: 16, color: Color(0xFF6B7280)),
                            label: const Text('달력',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280))),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                          )),
                          Container(
                              width: 1,
                              height: 22,
                              color: const Color(0xFFE5E7EB)),
                          Expanded(
                              child: TextButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit_outlined,
                                size: 16, color: _purple),
                            label: const Text('수정',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _purple)),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                          )),
                        ])
                      : Row(children: [
                          Expanded(
                              child: TextButton.icon(
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_forever_outlined,
                                size: 16, color: Color(0xFFF43F5E)),
                            label: const Text('완전삭제',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF43F5E))),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                          )),
                          Container(
                              width: 1,
                              height: 22,
                              color: const Color(0xFFE5E7EB)),
                          Expanded(
                              child: TextButton.icon(
                            onPressed: widget.onOpenCalendar,
                            icon: const Icon(Icons.calendar_today_outlined,
                                size: 16, color: Color(0xFF6B7280)),
                            label: const Text('달력보기',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280))),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                          )),
                        ]),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 6,
          bottom: 6,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: widget.enabled ? _purple : const Color(0xFFD1D5DB),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PayCell extends StatelessWidget {
  const _PayCell(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? const Color(0xFF059669)
                      : const Color(0xFF111827))),
        ],
      ),
    );
  }
}

class _PayBadge extends StatelessWidget {
  const _PayBadge(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final valueColor =
        highlight ? const Color(0xFF059669) : const Color(0xFF374151);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label 급여',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF))),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }
}

// ── 구독 배너 ──────────────────────────────────────────────────────
class _WorkerBanner extends StatelessWidget {
  const _WorkerBanner({
    required this.message,
    required this.color,
    required this.textColor,
    this.onUpgrade,
  });

  final String message;
  final Color color;
  final Color textColor;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          if (onUpgrade != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onUpgrade,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: textColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '플랜 업그레이드',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _taxKey(TaxConfig tax) {
  if (tax == TaxConfig.none) return 'none';
  if (tax == TaxConfig.biz33) return '3.3';
  if (tax == TaxConfig.day66) return '6.6';
  if (tax is TaxConfigCustomPercent) return 'c${tax.percent}';
  return 'none';
}

String _insKey(InsuranceConfig ins) {
  if (ins is InsuranceNone) return 'none';
  if (ins is InsuranceEmploymentOnly) return 'emp1';
  if (ins is InsuranceFour) return 'four8';
  return 'none';
}

String _surchargeKey(SurchargePolicy s) {
  return [
    s.weeklyHolidayEnabled ? 'w1' : 'w0',
    s.overtimeEnabled ? 'o1' : 'o0',
    s.overtimePercent,
    s.holidayEnabled ? 'h1' : 'h0',
    s.holidayPercent,
    s.nightEnabled ? 'n1' : 'n0',
    s.nightPercent,
  ].join('_');
}

String _payrollPolicyKey(PayrollPolicy p) {
  final cycle = p.cycle.name;
  final custom = p.customEveryDays ?? -1;
  final weekly = p.weeklyAnchor?.name ?? '-';
  final start = '${p.startFrom.year}-${p.startFrom.month}-${p.startFrom.day}';
  final mStart = p.monthlyStartDay ?? -1;

  final r = p.payRule;
  final rType = r.type.name;
  final rMonthly = r.monthlyDay ?? -1;
  final rPlus = r.plusDays ?? -1;
  final rFixed = r.fixedDate == null
      ? '-'
      : '${r.fixedDate!.year}-${r.fixedDate!.month}-${r.fixedDate!.day}';

  return '$cycle|c$custom|w$weekly|s$start|m$mStart|r$rType|md$rMonthly|pd$rPlus|fx$rFixed';
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
