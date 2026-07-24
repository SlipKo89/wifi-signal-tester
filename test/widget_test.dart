import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wifi_apk/main.dart';

void main() {
  testWidgets('App boots to the connection form', (tester) async {
    await tester.pumpWidget(const WifiApkApp());
    await tester.pump();

    // Before connecting, the connection form and Connect button are shown.
    expect(find.text('MikroTik connection'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });
}
