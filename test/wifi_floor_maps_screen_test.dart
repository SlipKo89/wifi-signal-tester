import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_apk/settings/settings_controller.dart';
import 'package:wifi_apk/ui/theme.dart';
import 'package:wifi_apk/ui/wifi_floor_plan_editor.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan.dart';
import 'package:wifi_apk/wifi_map/wifi_floor_plan_store.dart';

void main() {
  Future<SettingsController> settings() async {
    SharedPreferences.setMockInitialValues({'lang': 'en'});
    final value = SettingsController();
    await value.load();
    return value;
  }

  testWidgets('scaled editor fits a narrow screen without overflow',
      (tester) async {
    final store = WifiFloorPlanStore(
      directoryProvider: () async => Directory('/tmp/floor-editor-ui-unused'),
    );
    const plan = WifiFloorPlan(
      id: 'office',
      name: 'Office floor',
      widthMeters: 12,
      heightMeters: 8,
      cellSizeMeters: 0.5,
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: await settings(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: WifiFloorPlanEditor(plan: plan, store: store),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Office floor'), findsOneWidget);
    expect(find.text('Object'), findsOneWidget);
    expect(find.text('Measure'), findsOneWidget);
    expect(find.text('0.5 m'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(-220, 0),
    );
    await tester.pump();
    await tester.tap(find.text('Object'));
    await tester.pump();
    expect(find.text('Wall'), findsOneWidget);
    expect(find.text('Unknown material'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
