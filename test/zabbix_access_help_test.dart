import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/zabbix_access_help_screen.dart';

void main() {
  testWidgets('shows the exact least-privilege Zabbix method list',
      (tester) async {
    final settings = SettingsController();
    await settings.setLang('en');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: ZabbixAccessHelpScreen()),
      ),
    );

    expect(find.text('Zabbix read-only access'), findsOneWidget);
    expect(
      find.text('host.get\nitem.get\nhistory.get\ntrend.get'),
      findsOneWidget,
    );
    expect(find.textContaining('Super admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
