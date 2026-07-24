import 'package:flutter/material.dart';

import '../theme.dart';
import 'metric_tile.dart';

/// One side of the dashboard — either "Phone" or "Access point". Shows the
/// headline signal big, with a colour-coded strength bar and supporting
/// metrics below.
class SignalCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;

  /// Headline signal in dBm.
  final int? signalDbm;

  /// Supporting metrics as label→(value, unit).
  final List<MetricTile> metrics;

  /// Shown instead of the bar/metrics when [signalDbm] is null — explains why
  /// there is no reading (e.g. client not on a managed AP).
  final String? emptyHint;

  const SignalCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.signalDbm,
    required this.metrics,
    this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.signalColor(signalDbm);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  signalDbm?.toString() ?? '—',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('dBm',
                    style: TextStyle(color: Color(0xFF7D8590), fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            if (signalDbm == null && emptyHint != null)
              _EmptyHint(text: emptyHint!)
            else ...[
              _StrengthBar(dbm: signalDbm, color: color),
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 14,
                children: metrics,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: Color(0xFF7D8590)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9DA7B3), height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// Maps −90..−40 dBm to a 0..1 filled bar.
class _StrengthBar extends StatelessWidget {
  final int? dbm;
  final Color color;
  const _StrengthBar({required this.dbm, required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction =
        dbm == null ? 0.0 : ((dbm! + 90) / 50).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 6,
        backgroundColor: AppTheme.surfaceAlt,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
