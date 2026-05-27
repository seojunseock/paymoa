// lib/common/help_dialog.dart
import 'package:flutter/material.dart';

/// 공통 도움말 팝업 (X 버튼으로 닫기)
void showHelpDialog(BuildContext context,
    {required String title, required String body}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close_rounded,
                      size: 20, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(body,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF374151),
                    height: 1.65)),
          ],
        ),
      ),
    ),
  );
}

/// 도움말 ? 아이콘 버튼 (공통)
Widget helpIcon(BuildContext context,
    {required String title,
    required String body,
    Color color = const Color(0xFFB0B8C1)}) {
  return GestureDetector(
    onTap: () => showHelpDialog(context, title: title, body: body),
    child: Icon(Icons.help_outline_rounded, size: 16, color: color),
  );
}
