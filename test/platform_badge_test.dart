import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/ui/theme.dart';
import 'package:wifi_apk/ui/widgets/platform_badge.dart';

void main() {
  testWidgets('macOS alpha badge has a clear stable label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: MacOsAlphaBadge()),
      ),
    );

    expect(find.text('macOS ALPHA'), findsOneWidget);
  });
}
