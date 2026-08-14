import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/lte_screen.dart';
import 'package:wifi_apk/ui/theme.dart';

void main() {
  testWidgets('LTE connection form shows and selects saved routers',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'lte_routers_v2': jsonEncode([
        {
          'host': '192.0.2.1',
          'username': 'first-reader',
          'password': 'first-secret',
          'transport': 'ssh',
          'port': 2222,
          'interface': 'lte1',
        },
        {
          'host': '192.0.2.2',
          'username': 'second-reader',
          'password': 'second-secret',
          'transport': 'rest',
          'useTls': true,
        },
      ]),
    });
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const LteScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved LTE routers'), findsOneWidget);
    expect(find.text('192.0.2.1'), findsWidgets);
    expect(find.text('192.0.2.2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('192.0.2.2'));
    await tester.pump();
    final hostField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Host / IP',
      ),
    );
    expect(hostField.controller?.text, '192.0.2.2');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
