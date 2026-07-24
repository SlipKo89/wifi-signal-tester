import 'package:flutter/material.dart';

import '../metric_help.dart';

/// A single labelled value with an accent colour (e.g. "SNR · 28 dB").
///
/// If [helpKey] is set, tapping opens the reference sheet for that metric and a
/// small ⓘ hint is shown next to the label.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final String? helpKey;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.helpKey,
  });

  @override
  Widget build(BuildContext context) {
    final tile = _content();
    if (helpKey == null) return tile;
    return InkWell(
      onTap: () => showMetricHelp(context, helpKey!),
      borderRadius: BorderRadius.circular(6),
      child: tile,
    );
  }

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                color: Color(0xFF7D8590),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (helpKey != null) ...[
              const SizedBox(width: 3),
              const Icon(Icons.info_outline,
                  size: 9, color: Color(0xFF565E68)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color ?? Colors.white,
                fontFeatures: const [],
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7D8590),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
