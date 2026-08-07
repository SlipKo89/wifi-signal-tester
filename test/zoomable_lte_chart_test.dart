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

  testWidgets('LTE quality chart explains current and best result',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ZoomableLteChart(
              showQuality: true,
              technicalInitiallyExpanded: false,
              ru: true,
              datasets: [
                LteChartDataset(
                  name: 'Сейчас',
                  color: Colors.green,
                  points: [
                    LteChartPoint(
                      sampledAt: DateTime(2026),
                      quality: 81,
                      qualityConfidence: 1,
                      rsrp: -90,
                      rsrq: -9,
                      sinr: 20,
                    ),
                    LteChartPoint(
                      sampledAt: DateTime(2026, 1, 1, 0, 0, 3),
                      quality: 74,
                      qualityConfidence: 1,
                      rsrp: -94,
                      rsrq: -10,
                      sinr: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    expect(find.text('74'), findsOneWidget);
    expect(find.textContaining('лучшее 81'), findsOneWidget);
    expect(find.text('Показать технические графики'), findsOneWidget);
    expect(find.text('RSRP'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Показать технические графики'));
    await tester.pump();
    expect(find.text('RSRP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
