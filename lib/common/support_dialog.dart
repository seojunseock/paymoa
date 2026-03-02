// lib/common/support_dialog.dart
//
// 📦 pubspec.yaml 추가 필요:
//   url_launcher: ^6.2.0
//
// android/app/src/main/AndroidManifest.xml의 <queries> 블록에 추가:
//   <intent>
//     <action android:name="android.intent.action.SENDTO" />
//     <data android:scheme="mailto" />
//   </intent>

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 문의하기 팝업 + Gmail 전송
/// 사용법:
///   SupportDialog.show(context);
///   SupportDialog.show(context, isOwner: true);
class SupportDialog {
  static const _devEmail = 'paymoa8@gmail.com';

  static Future<void> show(BuildContext context, {bool isOwner = false}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _SupportDialogContent(
        isOwner: isOwner,
        devEmail: _devEmail,
      ),
    );
  }
}

class _SupportDialogContent extends StatefulWidget {
  const _SupportDialogContent({
    required this.isOwner,
    required this.devEmail,
  });

  final bool isOwner;
  final String devEmail;

  @override
  State<_SupportDialogContent> createState() => _SupportDialogContentState();
}

class _SupportDialogContentState extends State<_SupportDialogContent> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  static const _primary = Color(0xFF7C3AED);

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (subject.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해 주세요.')),
      );
      return;
    }

    setState(() => _sending = true);

    // Gmail 앱 또는 기본 메일 앱으로 이동
    final role = widget.isOwner ? '[사장님]' : '[알바생]';
    final encodedSubject = Uri.encodeComponent('$role $subject');
    final encodedBody = Uri.encodeComponent(body);

    final uri = Uri.parse(
      'mailto:${widget.devEmail}'
      '?subject=$encodedSubject'
      '&body=$encodedBody',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        if (mounted) Navigator.of(context).pop();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('메일 앱을 열 수 없어요. ${widget.devEmail}로 직접 보내주세요.'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 헤더 ─────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mail_outline_rounded,
                        color: _primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('문의하기',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Color(0xFF1F2937))),
                        SizedBox(height: 2),
                        Text('이메일로 전달돼요',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF9CA3AF), size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── 제목 ─────────────────────────────────────────
              const Text('제목',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151))),
              const SizedBox(height: 6),
              TextField(
                controller: _subjectCtrl,
                maxLength: 50,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: '문의 제목을 입력해 주세요',
                  hintStyle:
                      const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  counterText: '',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary, width: 1.4),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── 내용 ─────────────────────────────────────────
              const Text('내용',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151))),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                maxLines: 6,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '문의 내용을 자세히 입력해 주세요.\n'
                      '(버그 제보 시 어떤 상황에서 발생했는지 함께 적어주시면 더 빠르게 해결할 수 있어요)',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: Color(0xFFD1D5DB), height: 1.5),
                  counterText: '',
                  contentPadding: const EdgeInsets.all(14),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary, width: 1.4),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // 수신 이메일 안내
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '전송 시 ${widget.devEmail}로 이메일이 전달됩니다',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── 전송 버튼 ──────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('이메일로 전송',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
