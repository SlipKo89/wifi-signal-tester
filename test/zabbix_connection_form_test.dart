import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/zabbix_screen.dart';
import 'package:wifi_apk/zabbix/zabbix_credentials_store.dart';
import 'package:wifi_apk/zabbix/zabbix_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'lang': 'en'});
  });

  testWidgets('HTTP selection shows a cleartext token warning', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('HTTPS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTP').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP is not encrypted'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
  });

  testWidgets('saved HTTP profile restores its host and custom port',
      (tester) async {
    await ZabbixCredentialsStore().save(const ZabbixConnection(
      name: 'Lab',
      url: 'http://zabbix.lan:8080/zabbix',
      apiToken: 'test-token',
    ));

    await _pumpScreen(tester);

    expect(find.text('HTTP'), findsOneWidget);
    expect(find.text('zabbix.lan/zabbix'), findsOneWidget);
    expect(find.text('8080'), findsOneWidget);
    expect(find.textContaining('HTTP is not encrypted'), findsOneWidget);
  });
}

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = SettingsController();
  await settings.load();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(home: ZabbixScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
