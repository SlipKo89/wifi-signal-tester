import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'floor-plan picker uses a scoped document action and no media permission',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/slipko/wifi_apk/MainActivity.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(activity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(activity, contains('maxImageBytes = 25 * 1024 * 1024'));
    expect(activity, contains('maxProjectBytes = 35 * 1024 * 1024'));
    expect(activity, contains('call.method != "pickProject"'));
    expect(manifest, isNot(contains('READ_MEDIA_IMAGES')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });
}
