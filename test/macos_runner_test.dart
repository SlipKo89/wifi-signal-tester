import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS runner keeps the read-only network-client contract', () {
    final debug = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final release = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    for (final entitlements in [debug, release]) {
      expect(entitlements, contains('com.apple.security.app-sandbox'));
      expect(entitlements, contains('com.apple.security.network.client'));
      expect(
          entitlements, isNot(contains('com.apple.security.network.server')));
    }

    expect(info, contains('NSLocalNetworkUsageDescription'));
    expect(appInfo, contains('PRODUCT_NAME = Wi-Fi Signal Tester'));
    expect(
      appInfo,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.slipko.wifisignaltester'),
    );
  });
}
