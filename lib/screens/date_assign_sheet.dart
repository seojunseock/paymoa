// lib/screens/date_assign_sheet.dart
import 'package:flutter/material.dart';
import '../common/common_pickers.dart' as cp;

class DateAssignResult {
  final Set<DateTime> selectedDates; // UTC 00:00
  const DateAssignResult(this.selectedDates);
}

/// 근무 날짜 선택 시트(달력)
/// 내부 구현만 TableCalendar 기반 다이얼로그로 위임.
Future<DateAssignResult?> showDateAssignSheet(
  BuildContext context, {
  required Set<DateTime> existing, // UTC 00:00 날짜들
  required bool Function(DateTime dateUtc) checkConflict,
  DateTime? focusedDay,
  DateTime? firstDay,
  DateTime? lastDay,
}) async {
  final picked = await cp.showAlbaDatePickerDialog(
    context,
    initialUtc: existing,
    initialFocusedDay: focusedDay,
    firstDay: firstDay,
    lastDay: lastDay,
    checkConflict: checkConflict, // true면 비활성화
  );

  if (picked == null) return null;
  return DateAssignResult(picked);
}
