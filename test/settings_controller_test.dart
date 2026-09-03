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

  test('normal polling profile is the default', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    expect(settings.pollingProfile, PollingProfile.normal);
    expect(settings.pollSeconds, 2);
    expect(settings.healthPollSeconds, 15);
    expect(settings.identityPollSeconds, 30);
  });

  test('polling profile persists all independent intervals', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    await settings.setPollingProfile(PollingProfile.economical);

    final restored = SettingsController();
    await restored.load();
    expect(restored.pollingProfile, PollingProfile.economical);
    expect(restored.pollSeconds, 5);
    expect(restored.healthPollSeconds, 30);
    expect(restored.identityPollSeconds, 60);
  });

  test('legacy custom poll interval is preserved during migration', () async {
    SharedPreferences.setMockInitialValues({'pollSeconds': 7});
    final settings = SettingsController();
    await settings.load();

    expect(settings.pollingProfile, PollingProfile.custom);
    expect(settings.pollSeconds, 7);
    expect(settings.healthPollSeconds, 15);
    expect(settings.identityPollSeconds, 30);
  });

  test('custom polling intervals are bounded and persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    await settings.setPollSeconds(99);
    await settings.setHealthPollSeconds(1);
    await settings.setIdentityPollSeconds(999);

    final restored = SettingsController();
    await restored.load();
    expect(restored.pollingProfile, PollingProfile.custom);
    expect(restored.pollSeconds, 30);
    expect(restored.healthPollSeconds, 5);
    expect(restored.identityPollSeconds, 600);
  });
}
