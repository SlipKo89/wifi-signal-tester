import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/ui/widgets/roam_transition.dart';

void main() {
  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const RoamTransition(
                label: 'Последний переход',
                from: 'Очень длинное название первой точки доступа 5GHz',
                to: 'Ещё более длинное название второй точки доступа 5GHz',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('long AP names stay bounded in the horizontal layout',
      (tester) async {
    await pumpAtWidth(tester, 360);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('long AP names stay bounded on a narrow screen', (tester) async {
    await pumpAtWidth(tester, 240);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });
}
