import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wifi_apk/diagnostics/link_diagnostics.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/link_diagnostics_sheet.dart';
import 'package:wifi_apk/ui/theme.dart';

void main() {
  testWidgets('diagnostic card opens facts and advice', (tester) async {
    const report = LinkDiagnosticReport(
      sampleCount: 6,
      requiredSamples: 6,
      windowSeconds: 10,
      summary: LinkDiagnosticSummary(
        phoneRssi: -48,
        apSignal: -50,
        phoneSnr: 36,
        apSnr: 34,
        txCcq: 42,
        rxCcq: 47,
        phoneRateMbps: 300,
        apTxRateMbps: 288,
        apRxRateMbps: 240,
        pingAvgMs: 18,
        pingLossPct: 0,
        pingSamples: 6,
        cpuLoad: 24,
        delta: -2,
      ),
      findings: [
        LinkDiagnosticFinding(
          LinkIssueKind.lowCcq,
          LinkIssueSeverity.critical,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LinkDiagnosticsCard(
                report: report,
                phase: LinkDiagnosticPhase.complete,
                canStart: true,
                onStart: () {},
                onCancel: () {},
                apName: 'lab-ap',
                completedAt: DateTime(2026, 8, 7, 12, 30),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Strong signal, low CCQ'), findsOneWidget);
    await tester.tap(find.text('Strong signal, low CCQ'));
    await tester.pumpAndSettle();

    expect(find.text('Connection diagnosis'), findsOneWidget);
    expect(find.text('OBSERVED'), findsOneWidget);
    expect(find.text('WHAT TO CHECK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheduled diagnosis can be started immediately', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var starts = 0;
    const report = LinkDiagnosticReport(
      sampleCount: 0,
      requiredSamples: 6,
      windowSeconds: 0,
      summary: LinkDiagnosticSummary(),
      findings: [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: LinkDiagnosticsCard(
              report: report,
              phase: LinkDiagnosticPhase.waiting,
              waitSeconds: 8,
              apName: 'hAP ac3 very long roaming access point name',
              canStart: true,
              onStart: () => starts++,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    expect(
        find.text('Automatic measurement starts in 8 sec. You can run it now.'),
        findsOneWidget);
    await tester.tap(find.text('Run now'));
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });
}
