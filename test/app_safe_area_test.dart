import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/ui/widgets/app_safe_area.dart';

void main() {
  testWidgets('keeps the last control above Android system navigation',
      (tester) async {
    const screenSize = Size(360, 780);
    const navigationInset = 48.0;
    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: screenSize,
              padding: EdgeInsets.only(bottom: navigationInset),
              viewPadding: EdgeInsets.only(bottom: navigationInset),
            ),
            child: AppSafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: Key('last-control'),
                  height: 40,
                  width: 120,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final screenBottom = tester.getBottomRight(find.byType(Scaffold)).dy;
    final controlBottom =
        tester.getBottomRight(find.byKey(const Key('last-control'))).dy;
    expect(screenBottom - controlBottom, greaterThanOrEqualTo(navigationInset));
  });

  test('every app Scaffold uses the shared system-navigation inset policy', () {
    final missing = <String>[];
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      final scaffoldCount =
          RegExp(r'\bScaffold\s*\(').allMatches(source).length;
      if (scaffoldCount == 0) continue;
      final safeBodyCount =
          RegExp(r'body\s*:\s*AppSafeArea\s*\(').allMatches(source).length;
      if (safeBodyCount != scaffoldCount) {
        missing.add('${file.path}: $safeBodyCount/$scaffoldCount safe bodies');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Every full-screen app Scaffold must protect its last control '
          'from Android gesture and three-button navigation.\n'
          '${missing.join('\n')}',
    );
  });
}
