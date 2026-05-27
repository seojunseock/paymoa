// lib/payroll/payroll_document_service.dart
import 'dart:math';

import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';

import '../models/ui_calendar_models.dart';

import '../policies/policies.dart';
import '../policies/policy_mapper.dart' as pm;

import 'payroll_engine.dart';
import 'payroll_policy.dart';
import 'pay_calculator.dart';

/// ✅ 문서(엑셀/PDF/CSV) 생성용 “한 방 입력/출력”
class PayrollDocumentService {
  final PayrollEngine _engine;

  const PayrollDocumentService({PayrollEngine? engine})
      : _engine = engine ?? const PayrollEngine();

  /// ✅ (1) 지급분(정산기간) 기준 문서
  List<PayrollDocumentRow> buildPeriodDocument({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required PayPeriod period,
  }) {
    final Map<String, List<StoreSchedule>> byWorker = {};
    for (final s in schedules) {
      (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
    }

    final rows = <PayrollDocumentRow>[];

    for (final w in workers) {
      final ws = byWorker[w.workerUid] ?? const <StoreSchedule>[];

      final effectiveWage = _effectiveWage(store: store, worker: w);
      final effectivePayDay = _effectivePayDay(store: store, worker: w);
      final tax = _effectiveTax(store: store, worker: w);
      final insurance = _effectiveInsurance(store: store, worker: w);
      final surcharge = _effectiveSurcharge(store: store, worker: w);

      final basePolicy = store.payrollPolicy;
      final policy = basePolicy.copyWith(
        payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
      );

      // period에 겹치는 스케줄만 필터 (표시/집계용)
      final filtered = _filterSchedulesByPeriod(ws, period);
      final uiSchedules = filtered.map(_toUiSchedule).toList(growable: false);
      // 주휴수당 경계 주 계산용: 해당 작업자의 전체 스케줄
      final allUiSchedules = ws.map(_toUiSchedule).toList(growable: false);

      final alba = UICalendarAlba(
        id: w.workerUid,
        storeId: store.id,
        name: (w.displayName ?? w.workerUid),
        hourlyWage: effectiveWage,
        colorHex: 'FF000000',
        payDay: effectivePayDay,
      );

      final historySource =
          w.inheritFromStore ? store.policyHistory : w.policyHistory;

      int wageAtFn(String _, DateTime date) =>
          w.effectiveHourlyWageAt(store, date);
      SurchargePolicy surchargeAtFn(DateTime date) =>
          historySource.surchargeAt(date) ?? surcharge;
      TaxConfig taxAtFn(DateTime date) => historySource.taxAt(date) ?? tax;
      InsuranceConfig insuranceAtFn(DateTime date) =>
          historySource.insuranceAt(date) ?? insurance;

      final summary = _engine.summaryForDate(
        policy: policy,
        alba: alba,
        schedules: allUiSchedules,
        tax: tax,
        insurance: insurance,
        surchargePolicy: surcharge,
        wageAt: wageAtFn,
        surchargeAt: surchargeAtFn,
        taxAt: taxAtFn,
        insuranceAt: insuranceAtFn,
        anyDateInPeriod: period.start,
      );

      final workedMinutes = _sumWorkedMinutesLikeEngine(filtered);

      rows.add(
        PayrollDocumentRow(
          kind: PayrollDocumentKind.period,
          storeId: store.id,
          storeName: store.name,
          workerUid: w.workerUid,
          workerName: (w.displayName ?? w.workerUid),
          periodStart: summary.period.start,
          periodEnd: summary.period.end,
          payDate: summary.payDate,
          hourlyWage: wageAtFn(w.workerUid, summary.period.end),
          workedMinutes: workedMinutes,
          scheduleCount: filtered.length,
          gross: summary.gross,
          net: summary.net,
          weeklyHolidayPay: summary.weeklyHolidayPay,
          tax: taxAtFn(summary.period.end),
          insurance: insuranceAtFn(summary.period.end),
          surcharge: surchargeAtFn(summary.period.end),
          payrollPolicy: policy,
          changeNotes: _buildChangeNotesForRange(
            worker: w,
            history: historySource,
            rangeStart: period.start,
            rangeEnd: period.end,
          ),
        ),
      );
    }

    rows.sort((a, b) {
      final an = a.workerName.trim();
      final bn = b.workerName.trim();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return a.workerUid.compareTo(b.workerUid);
    });

    return rows;
  }

  /// ✅ (2) “년도+월” 기준 문서
  ///
  /// 변경 핵심:
  /// - 사용자가 선택한 year/month를 "근무한 달"이 아니라
  ///   "급여일이 속한 달"로 해석
  /// - 그 급여일에 대응하는 정산기간(period)을 찾고,
  ///   그 기간의 스케줄만 포함
  /// - 해당 기간에 기록이 없으면 그 알바 줄 자체를 만들지 않음
  List<PayrollDocumentRow> buildCalendarMonthDocument({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int month,
    DateTime? untilDate,
  }) {
    final Map<String, List<StoreSchedule>> byWorker = {};
    for (final s in schedules) {
      (byWorker[s.workerUid] ??= <StoreSchedule>[]).add(s);
    }

    final rows = <PayrollDocumentRow>[];

    for (final w in workers) {
      final wsAll = byWorker[w.workerUid] ?? const <StoreSchedule>[];

      final effectiveWage = _effectiveWage(store: store, worker: w);
      final effectivePayDay = _effectivePayDay(store: store, worker: w);
      final tax = _effectiveTax(store: store, worker: w);
      final insurance = _effectiveInsurance(store: store, worker: w);
      final surcharge = _effectiveSurcharge(store: store, worker: w);

      final basePolicy = store.payrollPolicy;
      final policy = basePolicy.copyWith(
        payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
      );

      // ✅ 선택한 월 안에 "급여일"이 있는 정산기간 찾기
      // 당일급여: period가 하루씩이므로 달력월(1~말일) 전체를 대상으로 처리
      final PayPeriod targetPeriod;
      if (policy.cycle == PayCycleType.daily) {
        final lastDay = DateTime(year, month + 1, 0).day;
        targetPeriod = PayPeriod(
          start: DateTime(year, month, 1),
          end: DateTime(year, month, lastDay),
        );
      } else {
        final resolved = _resolveTargetPeriodForPayMonth(
          policy: policy,
          year: year,
          month: month,
        );
        if (resolved == null) continue;
        targetPeriod = resolved.period;
      }

      // ✅ today/퇴사일 cutoff
      DateTime? workerCutoff = untilDate == null ? null : _dateOnly(untilDate);
      if (w.endedAt != null) {
        final ended = _dateOnly(w.endedAt!);
        workerCutoff = workerCutoff == null || ended.isBefore(workerCutoff)
            ? ended
            : workerCutoff;
      }

      var filtered = _filterSchedulesByPeriod(wsAll, targetPeriod);

      if (workerCutoff != null) {
        filtered = filtered.where((s) {
          final d = DateTime(s.year, s.month, s.day);
          return !d.isAfter(workerCutoff!);
        }).toList(growable: false);
      }

      // ✅ 해당 정산기간에 기록이 없으면 "줄 자체"를 만들지 않음
      if (filtered.isEmpty) continue;

      final uiSchedules = filtered.map(_toUiSchedule).toList(growable: false);
      // 주휴수당 경계 주 계산용: 해당 작업자의 전체 스케줄
      final allUiSchedules = wsAll.map(_toUiSchedule).toList(growable: false);

      final alba = UICalendarAlba(
        id: w.workerUid,
        storeId: store.id,
        name: (w.displayName ?? w.workerUid),
        hourlyWage: effectiveWage,
        colorHex: 'FF000000',
        payDay: effectivePayDay,
      );

      final historySource =
          w.inheritFromStore ? store.policyHistory : w.policyHistory;

      int wageAtFn(String _, DateTime date) =>
          w.effectiveHourlyWageAt(store, date);
      SurchargePolicy surchargeAtFn(DateTime date) =>
          historySource.surchargeAt(date) ?? surcharge;
      TaxConfig taxAtFn(DateTime date) => historySource.taxAt(date) ?? tax;
      InsuranceConfig insuranceAtFn(DateTime date) =>
          historySource.insuranceAt(date) ?? insurance;

      final workedMinutes = _sumWorkedMinutesLikeEngine(filtered);

      // 당일급여: 하루 단위 period이므로 각 날짜별 합산
      final int rowGross;
      final int rowNet;
      int rowWeeklyHolidayPay = 0;
      final DateTime rowPeriodStart;
      final DateTime rowPeriodEnd;
      final DateTime rowPayDate;

      if (policy.cycle == PayCycleType.daily) {
        final seenDays = <DateTime>{};
        int gSum = 0;
        int nSum = 0;
        for (final s in uiSchedules) {
          final day = DateTime(s.year, s.month, s.day);
          if (!seenDays.add(day)) continue;
          final ds = _engine.summaryForDate(
            policy: policy,
            alba: alba,
            schedules: allUiSchedules,
            tax: tax,
            insurance: insurance,
            surchargePolicy: surcharge,
            wageAt: wageAtFn,
            surchargeAt: surchargeAtFn,
            taxAt: taxAtFn,
            insuranceAt: insuranceAtFn,
            anyDateInPeriod: day,
          );
          gSum += ds.gross;
          nSum += ds.net;
          rowWeeklyHolidayPay += ds.weeklyHolidayPay;
        }
        rowGross = gSum;
        rowNet = nSum;
        rowPeriodStart = targetPeriod.start;
        rowPeriodEnd = targetPeriod.end;
        final lastDay = DateTime(year, month + 1, 0).day;
        rowPayDate = DateTime(year, month, effectivePayDay.clamp(1, lastDay));
      } else {
        final summary = _engine.summaryForDate(
          policy: policy,
          alba: alba,
          schedules: allUiSchedules,
          tax: tax,
          insurance: insurance,
          surchargePolicy: surcharge,
          wageAt: wageAtFn,
          surchargeAt: surchargeAtFn,
          taxAt: taxAtFn,
          insuranceAt: insuranceAtFn,
          anyDateInPeriod: targetPeriod.start,
        );
        rowGross = summary.gross;
        rowNet = summary.net;
        rowWeeklyHolidayPay = summary.weeklyHolidayPay;
        rowPeriodStart = summary.period.start;
        rowPeriodEnd = summary.period.end;
        rowPayDate = summary.payDate;
      }

      rows.add(
        PayrollDocumentRow(
          kind: PayrollDocumentKind.calendarMonth,
          storeId: store.id,
          storeName: store.name,
          workerUid: w.workerUid,
          workerName: (w.displayName ?? w.workerUid),
          periodStart: rowPeriodStart,
          periodEnd: rowPeriodEnd,
          payDate: rowPayDate,
          hourlyWage: wageAtFn(w.workerUid, rowPeriodEnd),
          workedMinutes: workedMinutes,
          scheduleCount: filtered.length,
          gross: rowGross,
          net: rowNet,
          weeklyHolidayPay: rowWeeklyHolidayPay,
          tax: taxAtFn(rowPeriodEnd),
          insurance: insuranceAtFn(rowPeriodEnd),
          surcharge: surchargeAtFn(rowPeriodEnd),
          payrollPolicy: policy,
          changeNotes: _buildChangeNotesForRange(
            worker: w,
            history: historySource,
            rangeStart: targetPeriod.start,
            rangeEnd: targetPeriod.end,
          ),
        ),
      );
    }

    rows.sort((a, b) {
      final an = a.workerName.trim();
      final bn = b.workerName.trim();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return a.workerUid.compareTo(b.workerUid);
    });

    return rows;
  }

  /* ─────────────────────────────────────────
     helpers
  ────────────────────────────────────────── */

  /// ✅ 선택한 급여월(year/month)에 대응하는 정산기간 찾기
  ///
  /// 예:
  /// - 2/15 ~ 3/14 근무
  /// - 3월 지급
  /// => year=2026, month=3 선택 시 이 period를 찾아야 함
  ({PayPeriod period, DateTime payDate})? _resolveTargetPeriodForPayMonth({
    required PayrollPolicy policy,
    required int year,
    required int month,
  }) {
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);

    // ✅ 전달/익월 걸침 대비 넉넉하게 탐색
    final scanStart = monthStart.subtract(const Duration(days: 62));
    final scanEnd = monthEnd.add(const Duration(days: 7));

    final seen = <String>{};

    for (DateTime d = scanStart;
        !d.isAfter(scanEnd);
        d = d.add(const Duration(days: 1))) {
      final preview = computePreviewForDate(
        policy: policy,
        anyDateInPeriod: d,
      );

      final key =
          '${preview.period.start.year}-${preview.period.start.month}-${preview.period.start.day}'
          '_${preview.period.end.year}-${preview.period.end.month}-${preview.period.end.day}'
          '_${preview.payDate.year}-${preview.payDate.month}-${preview.payDate.day}';

      if (!seen.add(key)) continue;

      if (preview.payDate.year == year && preview.payDate.month == month) {
        return (period: preview.period, payDate: preview.payDate);
      }
    }

    return null;
  }

  List<StoreSchedule> _filterSchedulesByPeriod(
    List<StoreSchedule> src,
    PayPeriod period,
  ) {
    final pStart = _dateOnly(period.start);
    final pEndEx = _dateOnly(period.end).add(const Duration(days: 1));

    final out = <StoreSchedule>[];
    for (final s in src) {
      final (schStart, schEnd) = _storeScheduleRange(s);
      if (_rangesOverlap(
        aStart: schStart,
        aEnd: schEnd,
        bStart: pStart,
        bEnd: pEndEx,
      )) {
        out.add(s);
      }
    }

    out.sort((a, b) {
      final ak = a.year * 10000 + a.month * 100 + a.day;
      final bk = b.year * 10000 + b.month * 100 + b.day;
      if (ak != bk) return ak.compareTo(bk);
      final am = a.startHour * 60 + a.startMinute;
      final bm = b.startHour * 60 + b.startMinute;
      return am.compareTo(bm);
    });

    return out;
  }

  int _sumWorkedMinutesLikeEngine(List<StoreSchedule> schedules) {
    int sum = 0;
    for (final s in schedules) {
      final (schStart, schEnd) = _storeScheduleRange(s);
      final totalMin = schEnd.difference(schStart).inMinutes;
      final workedMin = max(0, totalMin - s.breakMinutes.clamp(0, 1440));
      sum += workedMin;
    }
    return sum;
  }

  int _sumWorkedMinutesMonthly(List<StoreSchedule> schedules) {
    return _sumWorkedMinutesLikeEngine(schedules);
  }

  (DateTime start, DateTime end) _storeScheduleRange(StoreSchedule s) {
    final start = DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
    var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start, end);
  }

  bool _rangesOverlap({
    required DateTime aStart,
    required DateTime aEnd,
    required DateTime bStart,
    required DateTime bEnd,
  }) {
    final s = aStart.isAfter(bStart) ? aStart : bStart;
    final e = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    return e.isAfter(s);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _daysInMonth(int y, int m) {
    final firstNext = (m == 12) ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  UICalendarSchedule _toUiSchedule(StoreSchedule s) {
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
     effective resolvers
  ────────────────────────────────────────── */

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
    if (worker.inheritFromStore) return store.taxConfig;
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
    if (worker.inheritFromStore) return store.insuranceConfig;
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

  List<String> _buildChangeNotesForRange({
    required StoreWorker worker,
    required dynamic history,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final out = <String>[];

    final entries = _extractHistoryEntries(history);
    if (entries.isEmpty) return out;

    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);

    Map<String, dynamic>? prevRaw;
    for (final e in entries) {
      final effective = _extractEffectiveFrom(e);
      final raw = _extractRawPolicy(e);
      if (effective == null || raw == null) continue;

      if (effective.isBefore(start) || effective.isAfter(end)) {
        prevRaw = raw;
        continue;
      }

      final line = _buildSingleChangeLine(
        workerName: worker.displayName ?? worker.workerUid,
        effectiveFrom: effective,
        previous: prevRaw,
        current: raw,
      );

      if (line != null && line.trim().isNotEmpty) {
        out.add(line);
      }

      prevRaw = raw;
    }

    return out;
  }

  List<dynamic> _extractHistoryEntries(dynamic history) {
    if (history == null) return const [];

    final dynamic entries = history.entries;
    if (entries is List) return entries;

    if (history is List) return history;

    return const [];
  }

  DateTime? _extractEffectiveFrom(dynamic entry) {
    final raw = _extractRawPolicy(entry)?['effectiveFrom'];
    if (raw is String) {
      final p = raw.split('-');
      if (p.length < 3) return null;
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }
    if (raw is int) {
      final y = raw ~/ 10000;
      final m = (raw % 10000) ~/ 100;
      final d = raw % 100;
      if (y <= 0 || m <= 0 || d <= 0) return null;
      return DateTime(y, m, d);
    }
    if (raw is num) {
      final v = raw.toInt();
      final y = v ~/ 10000;
      final m = (v % 10000) ~/ 100;
      final d = v % 100;
      if (y <= 0 || m <= 0 || d <= 0) return null;
      return DateTime(y, m, d);
    }
    return null;
  }

  Map<String, dynamic>? _extractRawPolicy(dynamic entry) {
    final raw = entry?.rawPolicy;
    if (raw is Map) return raw.cast<String, dynamic>();
    if (entry is Map) return entry.cast<String, dynamic>();
    return null;
  }

  String? _buildSingleChangeLine({
    required String workerName,
    required DateTime effectiveFrom,
    required Map<String, dynamic>? previous,
    required Map<String, dynamic> current,
  }) {
    final changes = <String>[];

    _appendWageChange(changes, previous, current);
    _appendWeeklyHolidayChange(changes, previous, current);
    _appendOvertimeChange(changes, previous, current);
    _appendNightChange(changes, previous, current);
    _appendHolidayChange(changes, previous, current);
    _appendTaxChange(changes, previous, current);
    _appendInsuranceChange(changes, previous, current);

    if (changes.isEmpty) return null;

    final recordedAtRaw = current['recordedAt'];
    final dateLabel = recordedAtRaw is String && recordedAtRaw.isNotEmpty
        ? '수정일: $recordedAtRaw / 적용일: ${PayrollDocumentRow.fmtDate(effectiveFrom)}'
        : '적용일: ${PayrollDocumentRow.fmtDate(effectiveFrom)}';

    return '$workerName  $dateLabel  ${changes.join(', ')}';
  }

  void _appendWageChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevWage =
        _toInt(curr['previousHourlyWage']) ?? _toInt(prev?['hourlyWage']);
    final currWage = _toInt(curr['hourlyWage']);
    if (currWage == null) return;

    if (prevWage == null) {
      out.add('시급 ${_fmtWon(currWage)} 적용');
      return;
    }
    if (prevWage != currWage) {
      out.add('시급 ${_fmtWon(prevWage)}→${_fmtWon(currWage)}');
    }
  }

  void _appendWeeklyHolidayChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevPolicy =
        pm.surchargePolicyFromPolicy(prev ?? const <String, dynamic>{});
    final currPolicy = pm.surchargePolicyFromPolicy(curr);

    if (prevPolicy.weeklyHolidayEnabled != currPolicy.weeklyHolidayEnabled) {
      out.add('주휴 ${currPolicy.weeklyHolidayEnabled ? 'ON' : 'OFF'}');
    }

    if (currPolicy.weeklyHolidayEnabled) {
      if (prevPolicy.weeklyHolidayUseFixedMinutes !=
          currPolicy.weeklyHolidayUseFixedMinutes) {
        out.add(currPolicy.weeklyHolidayUseFixedMinutes
            ? '주휴 고정시간 적용'
            : '주휴 비례식 적용');
      } else if (currPolicy.weeklyHolidayUseFixedMinutes &&
          prevPolicy.weeklyHolidayFixedMinutes !=
              currPolicy.weeklyHolidayFixedMinutes) {
        out.add(
          '주휴 ${_fmtMinutes(prevPolicy.weeklyHolidayFixedMinutes)}→${_fmtMinutes(currPolicy.weeklyHolidayFixedMinutes)}',
        );
      }
    }
  }

  void _appendOvertimeChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevPolicy =
        pm.surchargePolicyFromPolicy(prev ?? const <String, dynamic>{});
    final currPolicy = pm.surchargePolicyFromPolicy(curr);

    if (prevPolicy.overtimeEnabled != currPolicy.overtimeEnabled) {
      out.add('연장근로 ${currPolicy.overtimeEnabled ? 'ON' : 'OFF'}');
    }

    if (currPolicy.overtimeEnabled) {
      if (prevPolicy.overtimeRule != currPolicy.overtimeRule) {
        out.add(
          '연장기준 ${_overtimeRuleLabel(prevPolicy.overtimeRule)}→${_overtimeRuleLabel(currPolicy.overtimeRule)}',
        );
      }
      if (prevPolicy.overtimePercent != currPolicy.overtimePercent) {
        out.add(
          '연장수당 ${prevPolicy.overtimePercent}%→${currPolicy.overtimePercent}%',
        );
      }
    }
  }

  void _appendNightChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevPolicy =
        pm.surchargePolicyFromPolicy(prev ?? const <String, dynamic>{});
    final currPolicy = pm.surchargePolicyFromPolicy(curr);

    if (prevPolicy.nightEnabled != currPolicy.nightEnabled) {
      out.add('야간수당 ${currPolicy.nightEnabled ? 'ON' : 'OFF'}');
    }
    if (currPolicy.nightEnabled &&
        prevPolicy.nightPercent != currPolicy.nightPercent) {
      out.add('야간수당 ${prevPolicy.nightPercent}%→${currPolicy.nightPercent}%');
    }
  }

  void _appendHolidayChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevPolicy =
        pm.surchargePolicyFromPolicy(prev ?? const <String, dynamic>{});
    final currPolicy = pm.surchargePolicyFromPolicy(curr);

    if (prevPolicy.holidayEnabled != currPolicy.holidayEnabled) {
      out.add('휴일수당 ${currPolicy.holidayEnabled ? 'ON' : 'OFF'}');
    }
    if (currPolicy.holidayEnabled &&
        prevPolicy.holidayPercent != currPolicy.holidayPercent) {
      out.add(
          '휴일수당 ${prevPolicy.holidayPercent}%→${currPolicy.holidayPercent}%');
    }
  }

  void _appendTaxChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevTax = pm.taxConfigFromPolicy(prev ?? const <String, dynamic>{});
    final currTax = pm.taxConfigFromPolicy(curr);
    final prevLabel = _taxLabel(prevTax);
    final currLabel = _taxLabel(currTax);
    if (prevLabel != currLabel) {
      out.add('세금 $prevLabel→$currLabel');
    }
  }

  void _appendInsuranceChange(
    List<String> out,
    Map<String, dynamic>? prev,
    Map<String, dynamic> curr,
  ) {
    final prevIns =
        pm.insuranceConfigFromPolicy(prev ?? const <String, dynamic>{});
    final currIns = pm.insuranceConfigFromPolicy(curr);
    final prevLabel = _insuranceLabel(prevIns);
    final currLabel = _insuranceLabel(currIns);
    if (prevLabel != currLabel) {
      out.add('보험 $prevLabel→$currLabel');
    }
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  String _fmtWon(int v) => '${v.toString()}원';

  String _fmtMinutes(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return '${h}시간 ${m}분';
    if (h > 0) return '${h}시간';
    return '${m}분';
  }

  String _overtimeRuleLabel(OvertimeRule rule) {
    switch (rule) {
      case OvertimeRule.dailyOver8:
        return '일 8시간 초과';
      case OvertimeRule.weeklyOver40:
        return '주 40시간 초과';
    }
  }

  String _taxLabel(TaxConfig tax) {
    if (tax == TaxConfig.none) return '없음';
    if (tax == TaxConfig.biz33) return '3.3%';
    if (tax == TaxConfig.day66) return '6.6%';
    if (tax is TaxConfigCustomPercent) return '${tax.percent}%';
    return '직접입력';
  }

  String _insuranceLabel(InsuranceConfig ins) {
    if (ins is InsuranceNone) return '없음';
    if (ins is InsuranceEmploymentOnly) return '고용보험';
    if (ins is InsuranceFour) return '4대보험';
    return '직접입력';
  }
}

enum PayrollDocumentKind {
  period,
  calendarMonth,
}

/// ✅ 엑셀/문서 출력용 Row 모델
class PayrollDocumentRow {
  final PayrollDocumentKind kind;

  final String storeId;
  final String storeName;

  final String workerUid;
  final String workerName;

  final DateTime periodStart; // 포함
  final DateTime periodEnd; // 포함
  final DateTime payDate;

  final int hourlyWage;
  final int workedMinutes;
  final int scheduleCount;

  final int gross;
  final int net;
  final int weeklyHolidayPay;

  final TaxConfig tax;
  final InsuranceConfig insurance;
  final SurchargePolicy surcharge;
  final PayrollPolicy payrollPolicy;
  final List<String> changeNotes;

  const PayrollDocumentRow({
    required this.kind,
    required this.storeId,
    required this.storeName,
    required this.workerUid,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.hourlyWage,
    required this.workedMinutes,
    required this.scheduleCount,
    required this.gross,
    required this.net,
    this.weeklyHolidayPay = 0,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.payrollPolicy,
    this.changeNotes = const [],
  });

  int get workedHoursFloor => workedMinutes ~/ 60;
  int get workedMinutesRemainder => workedMinutes % 60;

  String get workedTimeText =>
      '${workedHoursFloor}시간 ${workedMinutesRemainder}분';

  static String fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toExcelMap() {
    return {
      'kind': kind.name,
      'storeName': storeName,
      'workerName': workerName,
      'periodStart': fmtDate(periodStart),
      'periodEnd': fmtDate(periodEnd),
      'payDate': fmtDate(payDate),
      'hourlyWage': hourlyWage,
      'scheduleCount': scheduleCount,
      'workedMinutes': workedMinutes,
      'workedTime': workedTimeText,
      'gross': gross,
      'net': net,
      'changeNotes': changeNotes,
    };
  }
}
