// lib/export/export_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "문서/엑셀/CSV 내보내기"의 단일 진입점.
/// 1차 안정화에서는 기존 흐름(=CSV 문자열 생성 + 클립보드 복사)을 여기로 모읍니다.
/// 2차에서 share_plus / path_provider 등을 붙여 실제 파일 저장/메일 첨부까지 확장합니다.
class ExportService {
  const ExportService();

  Future<void> copyCsvToClipboard({
    required BuildContext context,
    required String csv,
    String successMessage = 'CSV가 클립보드에 복사됐어요.',
  }) async {
    await Clipboard.setData(ClipboardData(text: csv));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  }
}
