// lib/screens/work_editor_args.dart
import 'package:flutter/foundation.dart';

enum WorkEditorArgsMode { add, edit }

@immutable
class WorkEditorArgs {
  final WorkEditorArgsMode mode;

  /// 스타트→추가 시 자동 선택
  final String? preselectedAlbaId;

  /// 달력→추가 시 날짜 미리 지정
  final DateTime? presetDate;

  /// 수정 모드 시 필수
  final String? scheduleId;

  const WorkEditorArgs({
    required this.mode,
    this.preselectedAlbaId,
    this.presetDate,
    this.scheduleId,
  });
}
