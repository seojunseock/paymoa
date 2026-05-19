// lib/screens/owner/owner_worker_calendar_as_alba_screen.dart
import 'package:flutter/material.dart';

import '../../models/store.dart';
import '../../models/store_worker.dart';
import '../../models/store_schedule.dart';

import '../../data/firebase_service.dart';
import '../../policies/policies.dart';
import '../../policies/policy_mapper.dart' as pm;

import '../../payroll/payroll_policy.dart';

import '../../models/ui_calendar_models.dart';
import '../calendar_screen.dart';

class OwnerWorkerCalendarAsAlbaScreen extends StatefulWidget {
  const OwnerWorkerCalendarAsAlbaScreen({
    super.key,
    required this.store,
    required this.worker,
    this.endedAt,
  });

  final Store store;
  final StoreWorker worker;
  final DateTime? endedAt;

  @override
  State<OwnerWorkerCalendarAsAlbaScreen> createState() =>
      _OwnerWorkerCalendarAsAlbaScreenState();
}

class _OwnerWorkerCalendarAsAlbaScreenState
    extends State<OwnerWorkerCalendarAsAlbaScreen> {
  final _scheduleRepo = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final worker = widget.worker;

    return StreamBuilder<List<StoreSchedule>>(
      stream: _scheduleRepo.watchSchedulesForWorkerReadOnly(
        ownerUid: store.ownerUid,
        storeId: store.id,
        workerUid: worker.workerUid,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('달력')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('불러오기 실패\n${snap.error}'),
            ),
          );
        }

        final rawSchedules = snap.data ?? const <StoreSchedule>[];
        final endedAt = widget.endedAt;
        final schedules = endedAt == null
            ? rawSchedules
            : rawSchedules
                .where((s) => !DateTime(s.year, s.month, s.day).isAfter(
                    DateTime(endedAt.year, endedAt.month, endedAt.day)))
                .toList(growable: false);

        final effectiveWage = _effectiveWage(store: store, worker: worker);
        final effectivePayDay = _effectivePayDay(store: store, worker: worker);

        final effectiveTax = _effectiveTax(store: store, worker: worker);
        final effectiveInsurance =
            _effectiveInsurance(store: store, worker: worker);
        final effectiveSurcharge =
            _effectiveSurcharge(store: store, worker: worker);

        final alba = UICalendarAlba(
          id: worker.workerUid,
          storeId: store.id,
          name: (worker.displayName ?? worker.workerUid).trim().isEmpty
              ? worker.workerUid
              : worker.displayName!.trim(),
          hourlyWage: effectiveWage,
          colorHex: store.colorHex ?? '#3B82F6',
          payDay: effectivePayDay,
        );

        final uiSchedules = schedules
            .map(
              (s) => UICalendarSchedule(
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
              ),
            )
            .toList(growable: false);

        PayrollPolicy? payrollPolicyGetter(String albaId) {
          if (albaId != alba.id) return null;

          // 정산기간은 store.policy 그대로, 지급일만 worker의 effectivePayDay로 덮기
          final base = store.payrollPolicy;
          return base.copyWith(
            payRule: PayDateRule.nextMonthlyDay(effectivePayDay),
          );
        }

        // ✅ 날짜별 시급 반환 (overrideHourlyWage 우선 → policyHistory → effectiveWage)
        // 핵심버그 수정: 이전에는 policyHistory를 보지 않아 과거 근무도 현재 시급으로 표시됨
        final wagePh = worker.inheritFromStore
            ? store.policyHistory
            : worker.policyHistory;

        // policyHistory에서 날짜별 시급 밴드 빌드
        List<({DateTime from, int wage})> wageBands = [];
        if (wagePh.isNotEmpty) {
          final wageEntries = wagePh.entries
              .where((e) => e.rawPolicy['hourlyWage'] != null)
              .toList()
            ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
          if (wageEntries.isNotEmpty) {
            // 첫 번째 항목 이전 시급 (previousHourlyWage)
            final prevW = wageEntries.first.rawPolicy['previousHourlyWage'];
            if (prevW != null) {
              final pw = (prevW is int)
                  ? prevW
                  : (prevW is num)
                      ? prevW.toInt()
                      : int.tryParse('$prevW') ?? 0;
              if (pw > 0) wageBands.add((from: DateTime(1970), wage: pw));
            }
            for (final e in wageEntries) {
              final w = e.rawPolicy['hourlyWage'];
              final wage = (w is int)
                  ? w
                  : (w is num)
                      ? w.toInt()
                      : int.tryParse('$w') ?? 0;
              if (wage > 0) wageBands.add((from: e.effectiveFrom, wage: wage));
            }
          }
        }

        int wageAt(String albaId, DateTime dateLocal) {
          // 1) 해당 날짜 스케줄의 overrideHourlyWage 우선
          try {
            final match = schedules.firstWhere(
              (s) =>
                  s.year == dateLocal.year &&
                  s.month == dateLocal.month &&
                  s.day == dateLocal.day,
            );
            final override = match.overrideHourlyWage;
            if (override != null && override > 0) return override;
          } catch (_) {}

          // 2) policyHistory 밴드에서 날짜별 시급 조회
          if (wageBands.isNotEmpty) {
            final d0 = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
            int? last;
            for (final b in wageBands) {
              if (!b.from.isAfter(d0)) {
                last = b.wage;
              } else {
                break;
              }
            }
            if (last != null) return last;
          }

          // 3) fallback: 현재 유효 시급
          return effectiveWage;
        }

        return CalendarScreen(
          onBack: () => Navigator.of(context).pop(),
          albas: [alba],
          schedules: uiSchedules,

          // readOnly라 호출될 일 없음(그래도 안전하게 no-op)
          onDeleteSchedule: (_) async {},

          getTaxPolicy: (_) => effectiveTax,
          getInsurancePolicy: (_) => effectiveInsurance,
          getSurchargePolicy: (_) => effectiveSurcharge,
          getPayrollPolicy: payrollPolicyGetter,
          wageAt: wageAt,

          // readOnly라 열리지 않음
          openWorkEditor: (_) {},

          readOnly: true,
        );
      },
    );
  }
}

/* ─────────────────────────────────────────
   EFFECTIVE RESOLVERS (OwnerStoreDetail과 동일 로직)
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
