import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/state/monitor_controller.dart';
import 'package:wifi_apk/ui/mode_home_screen.dart';
import 'package:wifi_apk/ui/theme.dart';
import 'package:wifi_apk/ui/wifi_sites_screen.dart';

void main() {
  Future<SettingsController> settings() async {
    final value = SettingsController();
    await value.load();
    return value;
  }

  testWidgets('landing screen separates the three product modes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lang': 'en',
      'lastSeenVersion': '0.4.1',
    });
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final monitor = MonitorController();
    addTearDown(monitor.shutdown);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: await settings()),
        ChangeNotifierProvider.value(value: monitor),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const ModeHomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('MikroTik Wi-Fi'), findsOneWidget);
    expect(find.text('MikroTik LTE'), findsOneWidget);
    expect(find.text('Keenetic Wi-Fi'), findsOneWidget);
    expect(find.text('ALPHA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy routers appear as one imported MikroTik site',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'routers_v2': jsonEncode([
        {
          'host': '192.168.88.1',
          'username': 'monitor',
          'password': 'secret',
          'transport': 'auto',
          'useTls': true,
        },
        {
          'host': '192.168.88.2',
          'username': 'monitor',
          'password': 'secret',
          'transport': 'auto',
          'useTls': true,
        },
      ]),
    });
    SharedPreferences.setMockInitialValues({'lang': 'ru'});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final monitor = MonitorController();
    addTearDown(monitor.shutdown);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: await settings()),
        ChangeNotifierProvider.value(value: monitor),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const WifiSitesScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Импортированные роутеры'), findsOneWidget);
    expect(find.textContaining('2 роутера'), findsOneWidget);
    expect(find.text('Быстрое подключение без сохранения'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
