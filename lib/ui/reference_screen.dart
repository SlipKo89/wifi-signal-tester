import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../reference/metric_ref.dart';
import '../settings/settings_controller.dart';
import 'metric_help.dart';

/// Browsable reference of every metric the app shows.
class ReferenceScreen extends StatelessWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final refs = kMetricRefs.values.toList();
    return Scaffold(
      appBar: AppBar(title: Text(l.t('Reference', 'Справка'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: refs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MetricRefView(ref: refs[i]),
          ),
        ),
      ),
    );
  }
}
