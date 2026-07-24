import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../reference/metric_ref.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';

/// Opens the help sheet for a metric (by key from [kMetricRefs]).
void showMetricHelp(BuildContext context, String key) {
  final ref = kMetricRefs[key];
  if (ref == null) return;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: MetricRefView(ref: ref),
    ),
  );
}

/// Renders one [MetricRef] — used by both the tap sheet and the Reference screen.
class MetricRefView extends StatelessWidget {
  final MetricRef ref;
  const MetricRefView({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t(ref.titleEn, ref.titleRu),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(l.t(ref.whatEn, ref.whatRu),
            style: const TextStyle(
                fontSize: 13, color: Color(0xFFAAB2BD), height: 1.4)),
        if (ref.bands.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...ref.bands.map((b) => _bandRow(l.t(b.rangeEn, b.rangeRu),
              l.t(b.descEn, b.descRu), b.color)),
        ],
        if (ref.tipEn != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 15, color: Color(0xFF7D8590)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t(ref.tipEn!, ref.tipRu!),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF7D8590), height: 1.4)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _bandRow(String range, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(range,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child:
                  Text(desc, style: const TextStyle(fontSize: 12.5, height: 1.3)),
            ),
          ),
        ],
      ),
    );
  }
}
