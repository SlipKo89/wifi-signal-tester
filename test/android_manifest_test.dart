import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest keeps the read-only least-privilege contract', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final permissionTags = RegExp(
      r'<uses-permission\b[\s\S]*?/>',
    ).allMatches(manifest).map((m) => m.group(0)!).toList();

    String? permissionName(String tag) =>
        RegExp(r'android:name="([^"]+)"').firstMatch(tag)?.group(1);

    final activePermissions = permissionTags
        .where((tag) => !tag.contains('tools:node="remove"'))
        .map(permissionName)
        .whereType<String>()
        .toList();

    expect(activePermissions, [
      'android.permission.ACCESS_WIFI_STATE',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.INTERNET',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ]);

    for (final denied in [
      'android.permission.CHANGE_WIFI_STATE',
      'android.permission.CHANGE_NETWORK_STATE',
      'android.permission.WRITE_SETTINGS',
    ]) {
      expect(
        permissionTags,
        contains(predicate<String>((tag) =>
            permissionName(tag) == denied &&
            tag.contains('tools:node="remove"'))),
        reason: '$denied must be rejected during manifest merging',
      );
    }

    expect(manifest, isNot(contains('android.permission.NEARBY_WIFI_DEVICES')));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(
      File('android/app/src/main/res/values/strings.xml').readAsStringSync(),
      contains('<string name="app_name">Wi-Fi Signal Tester</string>'),
    );
  });
}
