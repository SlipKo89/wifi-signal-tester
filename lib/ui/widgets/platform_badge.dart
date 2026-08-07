import 'package:flutter/material.dart';

import '../theme.dart';

/// Marks the desktop build as an early preview without changing the app name.
class MacOsAlphaBadge extends StatelessWidget {
  const MacOsAlphaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.apAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.apAccent.withValues(alpha: 0.5),
        ),
      ),
      child: const Text(
        'macOS ALPHA',
        maxLines: 1,
        style: TextStyle(
          color: AppTheme.apAccent,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
