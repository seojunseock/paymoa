// lib/screens/owner/owner_store_detail_screen.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../models/store_schedule.dart';

import '../../common/ui/async_state_views.dart';
import '../../common/ui/bottom_cta.dart';

import '../../data/owner_worker_repository.dart';
import '../../data/owner_schedule_repository.dart';

import '../../policies/policies.dart';
import '../../policies/policy_mapper.dart' as pm;

import '../../payroll/payroll_engine.dart';
import '../../payroll/payroll_policy.dart';
import '../../payroll/payroll_document_service.dart';

import '../../models/ui_calendar_models.dart';

import 'owner_worker_form_screen.dart';
import 'owner_worker_schedule_screen.dart';

// ✅ 읽기전용 달력 화면(알바생 1명 + 내 매장 1개만)
import 'owner_worker_calendar_as_alba_screen.dart';

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
  final _workerRepo = OwnerWorkerRepository();
  final _scheduleRepo = OwnerScheduleRepository();
  final _engine = const PayrollEngine();
  final _docService = const PayrollDocumentService();

  bool _didEnsureSort = false;

  /// ✅ 근무자 수가 많아질 때 계산 부하 줄이기: 캐시(메모이제이션)
  final Map<String, _PayPairPreview> _payCache = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ sortIndex 레거시 보정 (화면 진입 1회)
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

    final wageText = store.defaultHourlyWage == null
        ? '미설정'
        : '${_comma(store.defaultHourlyWage!)}원';

    final payDayText = store.payDay == null ? '미설정' : '${store.payDay}일';

    // ✅ 초대 코드: storeCode 우선(없으면 id fallback)
    final joinCode =
        (store.storeCode != null && store.storeCode!.trim().isNotEmpty)
            ? store.storeCode!.trim()
            : store.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(store.name),
        centerTitle: false,
      ),
      body: StreamBuilder<List<StoreWorker>>(
        stream: _workerRepo.watchWorkers(
          ownerUid: store.ownerUid,
          storeId: store.id,
          activeOnly: false, // ✅ 여기서는 전체를 받고 화면에서 active만 보여줌
        ),
        builder: (context, wSnap) {
          if (wSnap.connectionState == ConnectionState.waiting) {
            return const AppLoadingView();
          }
          if (wSnap.hasError) {
            return AppErrorView(
              title: '근무자 목록을 불러오지 못했어요.',
              message: '${wSnap.error}',
              onRetry: () => (context as Element).markNeedsBuild(),
            );
          }

          final allWorkers = (wSnap.data ?? const <StoreWorker>[]);
          final activeWorkers =
              allWorkers.where((w) => w.isActive).toList(growable: false);

          // ✅ 장기 안정화: 화면에서는 "최근 N일"만 watch
          return StreamBuilder<List<StoreSchedule>>(
            stream: _scheduleRepo.watchRecentSchedulesForStore(
              ownerUid: store.ownerUid,
              storeId: store.id,
              recentDays: 120,
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

              // ✅ workerUid -> schedules 그룹핑(최근 N일)
              final Map<String, List<StoreSchedule>> byWorker = {};
              for (final s in schedulesRecent) {
                (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
              }

              // ✅ 캐시 정리(화면에 "표시되는(active)" 대상만 유지)
              final alive = activeWorkers.map((w) => w.workerUid).toSet();
              _payCache.removeWhere((k, _) => !alive.contains(k));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1) 매장 코드
                  _SectionCard(
                    title: '매장 코드',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          joinCode,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: joinCode),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('매장 코드가 복사되었습니다.'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('복사'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('QR/공유는 다음 단계에서 붙입니다.'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('QR'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(label: '기본 시급', value: wageText),
                        const SizedBox(height: 6),
                        _InfoRow(label: '급여일(매월)', value: payDayText),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 2) 문서받기
                  _SectionCard(
                    title: '문서 받기',
                    subtitle: '월 선택 / 지난 지급분 / 이번 지급분 (CSV 복사)',
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await _openDocumentSheet(
                                context: context,
                                store: store,
                                workers: allWorkers, // ✅ 문서는 ended 포함
                              );
                            },
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('급여명세/세무문서'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3) 근무자
                  Row(
                    children: [
                      Text(
                        '근무자',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${activeWorkers.length}명', // ✅ active만 카운트
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (activeWorkers.isEmpty)
                    AppEmptyView(
                      icon: Icons.people_alt_outlined,
                      title: '아직 근무자가 없어요.',
                      message: '알바생이 “매장 코드”로 참여하면 여기서 보입니다.',
                      action: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: joinCode),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('매장 코드가 복사되었습니다.')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('매장 코드 복사'),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activeWorkers.length,
                      onReorder: (oldIndex, newIndex) async {
                        final list = [...activeWorkers];
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = list.removeAt(oldIndex);
                        list.insert(newIndex, item);

                        await _workerRepo.reorderWorkers(
                          ownerUid: store.ownerUid,
                          storeId: store.id,
                          ordered: list, // ✅ active만 reorder
                        );
                      },
                      itemBuilder: (context, index) {
                        final w = activeWorkers[index];
                        final wsRaw =
                            byWorker[w.workerUid] ?? const <StoreSchedule>[];

                        // ✅ 안정된 캐시 키를 위해 정렬(날짜→시간)
                        final ws = [...wsRaw];
                        ws.sort((a, b) {
                          final ak = a.year * 10000 + a.month * 100 + a.day;
                          final bk = b.year * 10000 + b.month * 100 + b.day;
                          if (ak != bk) return ak.compareTo(bk);
                          final am = a.startHour * 60 + a.startMinute;
                          final bm = b.startHour * 60 + b.startMinute;
                          return am.compareTo(bm);
                        });

                        final payPair = _computePayPairCached(
                          store: store,
                          worker: w,
                          schedulesSorted: ws,
                        );

                        return Padding(
                          key: ValueKey('worker_${w.workerUid}'),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WorkerCard(
                            store: store,
                            worker: w,
                            pay: payPair,

                            // ✅ 기존: 일정보기 화면(리스트)
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OwnerWorkerScheduleScreen(
                                    ownerUid: store.ownerUid,
                                    storeId: store.id,
                                    storeName: store.name,
                                    worker: w,
                                  ),
                                ),
                              );
                            },

                            // ✅ 추가: 달력보기 화면(읽기 전용)
                            onOpenCalendar: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OwnerWorkerCalendarAsAlbaScreen(
                                    store: store,
                                    worker: w,
                                  ),
                                ),
                              );
                            },

                            onSettings: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OwnerWorkerFormScreen(
                                    store: store,
                                    worker: w,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomCta(
        icon: Icons.qr_code_2,
        label: '매장 코드 공유',
        onPressed: () async {
          final store = widget.store;
          final joinCode =
              (store.storeCode != null && store.storeCode!.trim().isNotEmpty)
                  ? store.storeCode!.trim()
                  : store.id;

          await Clipboard.setData(ClipboardData(text: joinCode));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('매장 코드가 복사되었습니다.')),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────
  // 문서: 버튼 눌렀을 때만 기간 fetch
  // ─────────────────────────────────────────

  Future<void> _openDocumentSheet({
    required BuildContext context,
    required Store store,
    required List<StoreWorker> workers,
  }) async {
    final now = DateTime.now(); // ✅ 폰 시간 기준
    final action = await showModalBottomSheet<_DocAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),

              // ✅ 요청한 순서: 월 선택 / 지난 / 이번
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('월 선택하기'),
                subtitle: Text('기본 ${now.year}년 · 년/월 선택'),
                onTap: () => Navigator.pop(ctx, _DocAction.pickMonth),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('지난 지급분'),
                onTap: () => Navigator.pop(ctx, _DocAction.prevPay),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('이번 지급분'),
                onTap: () => Navigator.pop(ctx, _DocAction.thisPay),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case _DocAction.prevPay:
        await _exportPrevPeriodCsv(
          context: context,
          store: store,
          workers: workers,
        );
        break;

      case _DocAction.thisPay:
        await _exportThisPeriodCsv(
          context: context,
          store: store,
          workers: workers,
        );
        break;

      case _DocAction.pickMonth:
        final picked = await _pickYearMonthWheel(context);
        if (!context.mounted || picked == null) return;

        await _exportMonthCsv(
          context: context,
          store: store,
          workers: workers,
          year: picked.year,
          month: picked.month,
        );
        break;
    }
  }

  /// ✅ 스크롤 휠(Year/Month) 선택
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
      isScrollControlled: false,
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
                            '월 내역 선택',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.pop(
                                ctx, _YearMonth(selectedYear, selectedMonth)),
                            child: const Text('선택'),
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
                              onSelectedItemChanged: (i) {
                                setState(() => selectedYear = years[i]);
                              },
                              children: [
                                for (final y in years)
                                  Center(
                                    child: Text(
                                      '$y년',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: monthController,
                              itemExtent: 44,
                              onSelectedItemChanged: (i) {
                                setState(() => selectedMonth = months[i]);
                              },
                              children: [
                                for (final m in months)
                                  Center(
                                    child: Text(
                                      '$m월',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
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

    await _withLoading(context, message: '이번 지급분 문서 준비 중…', () async {
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

      await _copyRowsAsCsv(
        context: context,
        title: '이번 지급분',
        rows: rows,
      );
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

    await _withLoading(context, message: '지난 지급분 문서 준비 중…', () async {
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

      await _copyRowsAsCsv(
        context: context,
        title: '지난 지급분',
        rows: rows,
      );
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
        context: context,
        title: '$year년 $month월 내역',
        rows: rows,
      );
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
    await Clipboard.setData(ClipboardData(text: csv));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title CSV가 복사되었습니다. (총 ${rows.length}명)'),
      ),
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

    final lines = <String>[];
    lines.add(header.join(','));

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
  // 카드 미리보기(지난/이번) - 최근 N일 데이터로만 계산
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

    // ✅ 정산기간 기준은 store.payrollPolicy로 통일 + 지급일만 덮기
    final basePolicy = store.payrollPolicy;
    final policy = basePolicy.copyWith(
      payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
    );

    // ✅ 캐시 키: 스케줄 updatedAt 최대값 + length 로 invalidate
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

    // ✅ StoreSchedule -> UICalendarSchedule
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
      );
    }).toList(growable: false);

    final alba = UICalendarAlba(
      id: worker.workerUid,
      storeId: store.id,
      name: (worker.displayName ?? worker.workerUid),
      hourlyWage: effectiveWage,
      colorHex: 'FF000000',
      payDay: effectivePayDay,
    );

    final now = DateTime.now();
    final thisSummary = _engine.summaryForDate(
      policy: policy,
      alba: alba,
      schedules: uiSchedules,
      tax: effectiveTax,
      insurance: effectiveInsurance,
      surchargePolicy: surcharge,
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
}

enum _DocAction { pickMonth, prevPay, thisPay }

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
    case 'basic':
    default:
      return WorkType.basic;
  }
}

/* ─────────────────────────────────────────
   UI
───────────────────────────────────────── */

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.store,
    required this.worker,
    required this.pay,
    required this.onTap,
    required this.onOpenCalendar,
    required this.onSettings,
  });

  final Store store;
  final StoreWorker worker;
  final _PayPairPreview pay;
  final VoidCallback onTap;
  final VoidCallback onOpenCalendar;
  final VoidCallback onSettings;

  String _name(StoreWorker w) {
    final dn = (w.displayName ?? '').trim();
    return dn.isEmpty ? w.workerUid : dn;
  }

  String _payLabel(DateTime payDate) => '${payDate.month}/${payDate.day} 지급분';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = _name(worker);
    final statusText = worker.isActive ? '재직중' : '퇴사';

    final prevLabel = _payLabel(pay.prev.payDate);
    final curLabel = _payLabel(pay.cur.payDate);

    final prevMoney = '${_comma(pay.prev.net)}원';
    final curMoney = '${_comma(pay.cur.net)}원';

    final taxPct = _taxPercent(pay.tax);
    final showTaxBadge = taxPct != null && taxPct > 0;

    final extraRows = <Widget>[];
    extraRows
        .add(_InfoRow(label: '시급', value: '${_comma(pay.effectiveWage)}원'));
    extraRows.add(_InfoRow(label: '급여일', value: '매월 ${pay.effectivePayDay}일'));

    if (showTaxBadge) {
      extraRows.add(_InfoRow(
        label: '세금',
        value: '${taxPct!.toStringAsFixed(taxPct % 1 == 0 ? 0 : 1)}%',
      ));
    }

    final insPct = _insurancePercent(pay.insurance);
    if (insPct != null && insPct > 0) {
      extraRows.add(_InfoRow(
        label: '보험',
        value: '${insPct.toStringAsFixed(insPct % 1 == 0 ? 0 : 1)}%',
      ));
    }

    final s = pay.surcharge;
    final anySurchargeEnabled = s.weeklyHolidayEnabled ||
        s.overtimeEnabled ||
        s.holidayEnabled ||
        s.nightEnabled;

    if (anySurchargeEnabled) {
      extraRows.add(const SizedBox(height: 10));
      extraRows.add(Text(
        '가산정책',
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
      ));
      extraRows.add(const SizedBox(height: 6));

      if (s.nightEnabled)
        extraRows.add(_InfoRow(label: '야간', value: '${s.nightPercent}%'));
      if (s.overtimeEnabled)
        extraRows.add(_InfoRow(label: '연장', value: '${s.overtimePercent}%'));
      if (s.holidayEnabled)
        extraRows.add(_InfoRow(label: '휴일', value: '${s.holidayPercent}%'));
      if (s.weeklyHolidayEnabled)
        extraRows.add(const _InfoRow(label: '주휴', value: '사용'));
    }

    return Material(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showTaxBadge) ...[
                              const SizedBox(width: 8),
                              _TinyBadge(
                                text:
                                    '세금 ${taxPct!.toStringAsFixed(taxPct % 1 == 0 ? 0 : 1)}%',
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        _MoneyLine(label: prevLabel, value: prevMoney),
                        const SizedBox(height: 2),
                        _MoneyLine(label: curLabel, value: curMoney),
                        const SizedBox(height: 4),
                        Text(
                          statusText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '설정',
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
                  title: Text(
                    '자세히 보기',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  children: [
                    // ✅ 버튼 2개: 일정보기 / 달력보기
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onTap,
                            icon: const Icon(Icons.list_alt_outlined),
                            label: const Text('일정보기'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onOpenCalendar,
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: const Text('달력보기'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    ...extraRows.map((w) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: w,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: theme.colorScheme.primary.withOpacity(0.12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/* ─────────────────────────────────────────
   helpers
───────────────────────────────────────── */

double? _taxPercent(TaxConfig tax) {
  if (tax == TaxConfig.none) return null;
  if (tax == TaxConfig.biz33) return 3.3;
  if (tax == TaxConfig.day66) return 6.6;
  if (tax is TaxConfigCustomPercent) return max(0.0, tax.percent);
  return null;
}

double? _insurancePercent(InsuranceConfig ins) {
  if (ins is InsuranceNone) return null;
  if (ins is InsuranceEmploymentOnly) return 1.0;
  if (ins is InsuranceFour) return 8.0;
  return null;
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
