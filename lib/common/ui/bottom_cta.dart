// lib/common/ui/bottom_cta.dart
import 'dart:async';

import 'package:flutter/material.dart';

class BottomCta extends StatelessWidget {
  const BottomCta({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  /// async 함수도 받을 수 있게 FutureOr<void>
  final FutureOr<void> Function()? onPressed;
  final String label;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: FilledButton.icon(
        onPressed: enabled && onPressed != null
            ? () {
                final r = onPressed!.call();
                if (r is Future) {
                  // ignore: discarded_futures
                  unawaited(r);
                }
              }
            : null,
        icon: Icon(icon ?? Icons.check),
        label: Text(label),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    );
  }
}
