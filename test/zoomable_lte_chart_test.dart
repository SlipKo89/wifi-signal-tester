import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/ui/widgets/zoomable_lte_chart.dart';

void main() {
  testWidgets('LTE chart zooms without overflowing a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final points = [
      for (var index = 0; index < 120; index++)
        LteChartPoint(
          sampledAt: DateTime(2026).add(Duration(seconds: index * 3)),
          rsrp: -105 + (index % 12),
          rsrq: -14 + (index % 5),
          sinr: 4 + (index % 14),
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ZoomableLteChart(
              datasets: [
                LteChartDataset(
                  name: 'Live',
                  color: Colors.green,
                  points: points,
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    expect(find.text('1×'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
