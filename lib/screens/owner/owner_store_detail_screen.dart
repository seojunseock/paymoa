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
import '../../payroll/payroll_policy.dart';
import '../../payroll/payroll_document_service.dart';

import '../../models/ui_calendar_models.dart';

class OwnerStoreDetailScreen extends StatefulWidget {
  const OwnerStoreDetailScreen({
    super.key,
    required this.store,
  });

  final Store store;

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
              recentDays: 365,
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

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
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

                  // ── 급여대장 다운로드 ──
                  Row(
                    children: [
                      // 왼쪽: 지난달 받기
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _exportPastMonth(
                              store, activeWorkers),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_month,
                                    size: 18, color: Color(0xFF6B7280)),
                                SizedBox(width: 6),
                                Text(
                                  '지난달 받기',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 오른쪽: 이번 달 급여대장
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _exportThisMonth(
                              store, activeWorkers, schedulesRecent),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF7C3AED).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.download,
                                    size: 18, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  '이번 달 급여대장',
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
                      ),
                    ],
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
                    ...activeWorkers.map((w) {
                      final wsRaw =
                          byWorker[w.workerUid] ?? const <StoreSchedule>[];
                      final ws = [...wsRaw]..sort(_scheduleSort);

                      final payPair = _computePayPairCached(
                        store: store,
                        worker: w,
                        schedulesSorted: ws,
                      );

                      return Padding(
                        key: ValueKey('active_${w.workerUid}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _WorkerSimpleCard(
                          enabled: true,
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
                        final ws = [...wsRaw]..sort(_scheduleSort);

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
                            ),
                            onEdit: () => AppNav.openOwnerWorkerSettings(
                              context,
                              store: store,
                              worker: w,
                              workerSchedules:
                                  byWorker[w.workerUid] ?? const [],
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
    final defaultYear = now.year;
    final defaultMonth = now.month;

    final years = <int>[];
    for (int y = defaultYear - 3; y <= defaultYear + 1; y++) {
      years.add(y);
    }
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

      // TODO(2차): exported(ended) worker의 이름 익명 처리 + 근무 있는 기간만 포함 규칙 반영은
      // PayrollDocumentService에서 처리하는게 정석.
      final rows = _docService.buildPeriodDocument(
        store: store,
        workers: workers,
        schedules: schedulesAll,
        period: period,
      );

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

  // ─────────────────────────────────────────
  // Export worker 2-step
  // ─────────────────────────────────────────

  Future<void> _onExportWorker({
    required Store store,
    required StoreWorker worker,
  }) async {
    // active 알바생만 내보낼 수 있음
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

  // ─────────────────────────────────────────
  // Pay preview (cached)
  // ─────────────────────────────────────────

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
        overrideHourlyWage: s.overrideHourlyWage, // ✅ 날짜별 시급 반영
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
    // ✅ 날짜별 가산정책 콜백 (policyHistory 기반)
    // inheritFromStore=true → 매장 policyHistory 사용
    // inheritFromStore=false → 개인 policyHistory 사용
    final ph =
        worker.inheritFromStore ? store.policyHistory : worker.policyHistory;
    SurchargePolicy Function(DateTime)? surchargeAtFn;
    if (ph.isNotEmpty) {
      surchargeAtFn = (date) => ph.surchargeAt(date) ?? surcharge;
    }

    // ✅ 날짜별 시급 콜백 (policyHistory에서 wageBands 빌드)
    // overrideHourlyWage=null 스케줄에서도 날짜별 정확한 시급 반환
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
        // ✅ 선행 밴드 (첫 번째 변경 이전 시급)
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
              if (!b.from.isAfter(d0))
                last = b.wage;
              else
                break;
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
      surchargeAt: surchargeAtFn, // ✅ 날짜별 정책 이력
      wageAt: wageAtFn, // ✅ 날짜별 시급
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
      surchargeAt: surchargeAtFn, // ✅ 날짜별 정책 이력
      wageAt: wageAtFn, // ✅ 날짜별 시급
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

  /// 이번 달 급여대장 생성 + 공유
  Future<void> _exportThisMonth(
    Store store,
    List<StoreWorker> workers,
    List<StoreSchedule> schedules,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final service = PayrollExcelService();
      await service.generateAndSharePayroll(
        store: store,
        workers: workers,
        schedules: schedules,
      );

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이번 달 급여대장을 공유했습니다!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 지난달 급여대장 생성 + 공유 (월 선택)
  Future<void> _exportPastMonth(
    Store store,
    List<StoreWorker> workers,
  ) async {
    final picked = await _pickYearMonthWheel(context);
    if (!mounted || picked == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // ✅ 선택한 월의 스케줄을 직접 조회 (watchRecentSchedulesForStore는 120일만 커버)
      final startOfMonth = DateTime(picked.year, picked.month, 1);
      final endOfMonth = DateTime(picked.year, picked.month + 1, 0);
      final monthSchedules = await _scheduleRepo.fetchSchedulesForStoreInRange(
        ownerUid: store.ownerUid,
        storeId: store.id,
        startInclusive: startOfMonth,
        endInclusive: endOfMonth,
      );

      final service = PayrollExcelService();
      await service.generatePayrollForMonth(
        store: store,
        workers: workers,
        schedules: monthSchedules,
        year: picked.year,
        month: picked.month,
      );

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${picked.year}년 ${picked.month}월 급여대장을 공유했습니다!'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류: $e'),
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

/* ─────────────────────────────────────────
   PAY MODELS
───────────────────────────────────────── */

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

/* ─────────────────────────────────────────
   POLICY / EFFECTIVE RESOLVERS
───────────────────────────────────────── */

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

/* ─────────────────────────────────────────
   UI helpers
───────────────────────────────────────── */

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

String _payLabel(DateTime payDate) => '${payDate.month}월';
String _badgeText({required StoreWorker worker}) =>
    worker.inheritFromStore ? '기본' : '개인';

/* ─────────────────────────────────────────
   UI Widgets
───────────────────────────────────────── */

// ── 초대 코드 한 줄 ─────────────────────────
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

// ── 문서 받기 행 ──────────────────────────────
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.store,
    required this.onPickMonth,
    required this.onThisMonth,
  });
  final Store store;
  final VoidCallback onPickMonth;
  final VoidCallback onThisMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // 급여일 기준 계산 (급여일 + 10일까지 현재달, 이후 다음달)
    final payDay = (store.payDay ?? 15).clamp(1, 28);
    final cutoffDay = (payDay + 10).clamp(1, 31);

    // 현재 날짜가 cutoff를 넘었는지 확인
    final passedCutoff = now.day > cutoffDay;

    // 표시할 월 결정
    final targetMonth =
        passedCutoff ? (now.month == 12 ? 1 : now.month + 1) : now.month;

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: onPickMonth,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.calendar_month_outlined,
                  size: 18, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              const Text('기간 선택',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151))),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: GestureDetector(
          onTap: onThisMonth,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.download_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text('${targetMonth}월 문서',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ]),
          ),
        ),
      ),
    ]);
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
  });

  final bool enabled;
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

  @override
  State<_WorkerSimpleCard> createState() => _WorkerSimpleCardState();
}

class _WorkerSimpleCardState extends State<_WorkerSimpleCard> {
  bool _expanded = false;
  static const _purple = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final opacity = widget.enabled ? 1.0 : 0.5;
    // 가산정책 활성화 항목들
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
              // ✅ 항상 시급 + 급여 표시 (접힘/펼침 모두 동일)
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
                // ✅ 가산정책 적용 항목
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
                // 버튼 (active: 내보내기/달력/수정, inactive: 달력/수정만)
                SizedBox(
                  height: 44,
                  child: Row(children: [
                    if (widget.enabled) ...[
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
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      )),
                      Container(
                          width: 1, height: 22, color: const Color(0xFFE5E7EB)),
                    ],
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
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    )),
                    Container(
                        width: 1, height: 22, color: const Color(0xFFE5E7EB)),
                    Expanded(
                        child: TextButton.icon(
                      onPressed: widget.enabled ? widget.onEdit : null,
                      icon: Icon(Icons.edit_outlined,
                          size: 16,
                          color: widget.enabled
                              ? _purple
                              : const Color(0xFFD1D5DB)),
                      label: Text('수정',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: widget.enabled
                                  ? _purple
                                  : const Color(0xFFD1D5DB))),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    )),
                  ]),
                ),
              ],
            ),
          ),
        ),
        // 컬러 바
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

// 접힌 상태에 보이는 급여 배지
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

/* ─────────────────────────────────────────
   helpers
───────────────────────────────────────── */

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
