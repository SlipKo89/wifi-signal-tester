import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/router/router_connection.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/theme.dart';
import 'package:wifi_apk/ui/widgets/connection_form.dart';

void main() {
  testWidgets('saved Keenetic profile restores the Alpha connection form',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'routers_v2': jsonEncode([
        {
          'vendor': 'keenetic',
          'host': 'router.example',
          'username': 'monitor',
          'password': 'secret',
          'transport': 'auto',
          'useTls': true,
        },
      ]),
    });
    SharedPreferences.setMockInitialValues({'lang': 'en'});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsController(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectionForm(
                vendor: RouterVendor.keenetic,
                onConnect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keenetic Wi-Fi · Alpha'), findsOneWidget);
    expect(find.text('HTTPS RCI · x-ndw2'), findsOneWidget);
    expect(find.textContaining('Runner 4G (KN-2212)'), findsOneWidget);
    expect(find.textContaining('KeeneticOS 5.01.C.3.0-1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
