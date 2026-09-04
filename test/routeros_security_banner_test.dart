import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/l10n/l10n.dart';
import 'package:wifi_apk/routeros_updates/routeros_security.dart';
import 'package:wifi_apk/ui/widgets/routeros_security_banner.dart';

void main() {
  testWidgets('several security warnings fit a narrow phone screen',
      (tester) async {
    final catalog = RouterOsSecurityCatalog.bundled;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: RouterOsSecurityBanner(
            l: const L10n(true),
            checking: true,
            warnings: [
              RouterOsSecurityStatus(
                host: 'router-with-a-very-long-hostname.example',
                installedVersion: '7.23.3 (stable)',
                fixedVersion: '7.23.4',
                catalog: catalog,
              ),
              RouterOsSecurityStatus(
                host: '192.168.175.2',
                installedVersion: '6.49.20 (long-term)',
                fixedVersion: '6.49.21',
                catalog: catalog,
              ),
            ],
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(
        find.text('Важное обновление безопасности RouterOS'), findsOneWidget);
    expect(find.text('Подробнее'), findsOneWidget);
  });
}
