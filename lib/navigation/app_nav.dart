// lib/navigation/app_nav.dart
import 'package:flutter/material.dart';

import '../models/ui_calendar_models.dart';
import '../screens/join_store_sheet.dart';
import '../screens/work_editor_args.dart' as wargs;
import '../screens/work_editor_screen.dart';

import '../policies/policies.dart' as pol;
import '../policies/policy_sheet.dart'; // ✅ PolicySheetResult

// ✅ owner screens (철도 확장)
import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';
import '../screens/owner/owner_store_detail_screen.dart';
import '../screens/owner/owner_store_form_screen.dart';
import '../screens/owner/owner_worker_form_screen.dart';
import '../screens/owner/owner_worker_calendar_as_alba_screen.dart';

/// 네비게이션/시트 호출을 한 곳으로 모아 "연결 끊김"을 줄이는 장기 안정화용 래퍼.
///
/// 원칙:
/// - 화면들은 Navigator를 직접 만지지 않고 AppNav만 호출한다.
/// - async 이후에는 context.mounted를 체크한다.
class AppNav {
  // ─────────────────────────────────────────
  // Sheets
  // ─────────────────────────────────────────

  static Future<JoinStoreSheetResult?> openJoinStoreSheet(
    BuildContext context,
  ) async {
    return showModalBottomSheet<JoinStoreSheetResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const JoinStoreSheet(),
    );
  }

  static Future<void> openWorkEditorSheet({
    required BuildContext context,
    required wargs.WorkEditorArgs args,
    required List<UICalendarAlba> albas,
    required List<UICalendarSchedule> schedules,
    required Future<void> Function(UICalendarSchedule s) onAdd,
    required Future<void> Function(UICalendarSchedule s) onUpdate,
    required Future<void> Function(String scheduleId) onDelete,
    pol.SurchargePolicy? Function(String albaId)? getSurchargePolicy,
    Future<void> Function(String albaId, PolicySheetResult result)?
        onUpdatePolicy,
    // ✅ 날짜 기반 시급 조회 (policyHistory 기준)
    int Function(String albaId, DateTime date)? wageAt,
  }) async {
    await showWorkEditorSheet(
      context: context,
      args: args,
      albas: albas,
      schedules: schedules,
      onAdd: onAdd,
      onUpdate: onUpdate,
      onDelete: onDelete,
      getSurchargePolicy: getSurchargePolicy,
      onUpdatePolicy: onUpdatePolicy,
      wageAt: wageAt,
    );
  }

  // ─────────────────────────────────────────
  // Owner flows (철도 확장)
  // ─────────────────────────────────────────

  static Future<void> openOwnerStoreDetail({
    required BuildContext context,
    required Store store,
    bool isReadOnly = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OwnerStoreDetailScreen(
          store: store,
          isReadOnly: isReadOnly,
        ),
      ),
    );
  }

  static Future<bool?> openOwnerStoreCreate(BuildContext context) async {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const OwnerStoreFormScreen(),
      ),
    );
  }

  static Future<bool?> openOwnerStoreEdit({
    required BuildContext context,
    required Store store,
  }) async {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OwnerStoreFormScreen(existing: store),
      ),
    );
  }

  // ✅ 근무자 달력 보기 (owner_store_detail에서 호출)
  static Future<void> openOwnerWorkerCalendar(
    BuildContext context, {
    required Store store,
    required StoreWorker worker,
    DateTime? endedAt,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerWorkerCalendarAsAlbaScreen(
          store: store,
          worker: worker,
          endedAt: endedAt,
        ),
      ),
    );
  }

  // ✅ 근무자 설정 (owner_store_detail에서 호출)
  static Future<void> openOwnerWorkerSettings(
    BuildContext context, {
    required Store store,
    required StoreWorker worker,
    List<StoreSchedule> workerSchedules = const [], // ✅ effectiveFrom 적용용
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerWorkerFormScreen(
          store: store,
          worker: worker,
          workerSchedules: workerSchedules,
        ),
      ),
    );
  }
}
