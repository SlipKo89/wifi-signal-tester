import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/settings/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection diagnosis settings persist', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    expect(settings.autoLinkDiagnostics, isTrue);
    expect(settings.linkDiagnosticDelaySeconds, 10);

    await settings.setAutoLinkDiagnostics(false);
    await settings.setLinkDiagnosticDelaySeconds(23);

    final restored = SettingsController();
    await restored.load();
    expect(restored.autoLinkDiagnostics, isFalse);
    expect(restored.linkDiagnosticDelaySeconds, 23);
  });

  test('connection diagnosis delay is bounded', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    await settings.setLinkDiagnosticDelaySeconds(99);
    expect(settings.linkDiagnosticDelaySeconds, 30);

    await settings.setLinkDiagnosticDelaySeconds(-5);
    expect(settings.linkDiagnosticDelaySeconds, 0);
  });
}
