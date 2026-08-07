import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wifi_apk/lte/lte_alignment.dart';
import 'package:wifi_apk/lte/lte_controller.dart';
import 'package:wifi_apk/lte/lte_signal.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/lte_alignment_screen.dart';
import 'package:wifi_apk/ui/theme.dart';

void main() {
  testWidgets('alignment guide stays bounded on a narrow phone screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final monitor = LteController();
    addTearDown(monitor.dispose);
    final session = LteAlignmentSession()
      ..add(
        const LteAlignmentTarget(round: 0, x: 0, y: 0),
        _window(),
      );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: LteAlignmentScreen(monitor: monitor, session: session),
        ),
      ),
    );

    expect(find.text('Alignment guide'), findsOneWidget);
    expect(find.text('I moved — measure'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pump();
    expect(find.text('Best checkpoint'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

List<LteSignal> _window() => [
      for (var index = 0; index < 6; index++)
        LteSignal(
          sampledAt: DateTime(2026, 8, 7).add(Duration(seconds: index * 2)),
          interfaceName: 'lte1',
          registered: true,
          rsrp: -96,
          rsrq: -10,
          sinr: 16,
          cqi: 10,
          band: 'B7',
          cellId: 'cell-a',
        ),
    ];
