// lib/screens/work_editor_args.dart
import 'package:flutter/foundation.dart';

enum WorkEditorArgsMode { add, edit }

@immutable
class WorkEditorArgs {
  final WorkEditorArgsMode mode;
  final String? preselectedAlbaId; // 스타트→추가 시 자동 선택
  final DateTime? presetDate;      // 달력→추가 시 날짜 미리 지정
  final String? scheduleId;        // 수정 모드 시 필수

  const WorkEditorArgs({
    required this.mode,
    this.preselectedAlbaId,
    this.presetDate,
    this.scheduleId,
  });
}
