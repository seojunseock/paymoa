// lib/common/ui/money_text_controller.dart
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class MoneyTextController extends TextEditingController {
  MoneyTextController({int? initialValue})
      : super(text: _fmt(initialValue ?? 0));

  static final digitsOnlyFormatter = FilteringTextInputFormatter.digitsOnly;

  /// 현재 입력값을 int로
  int get valueInt {
    final raw = text.replaceAll(',', '').trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  /// 값 설정 (int)
  void setValueInt(int v) {
    final clamped = v < 0 ? 0 : v;
    text = _fmt(clamped);
    selection = TextSelection.fromPosition(TextPosition(offset: text.length));
  }

  /// (원하면) setter 형태도 제공
  set valueIntSet(int v) => setValueInt(v);

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      b.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }
}
