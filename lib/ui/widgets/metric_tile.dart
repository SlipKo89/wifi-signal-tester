import 'package:flutter/material.dart';

/// A single labelled value with an accent colour (e.g. "SNR · 28 dB").
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? color;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
