import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wifi_apk/ui/widgets/metric_tile.dart';

void main() {
  testWidgets('MetricTile renders label, value and unit', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MetricTile(label: 'SNR', value: '41', unit: 'dB'),
      ),
    ));

    expect(find.text('SNR'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('dB'), findsOneWidget);
  });
}
