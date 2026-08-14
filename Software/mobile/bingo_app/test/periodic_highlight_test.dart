import 'package:bingo_app/src/widgets/periodic_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('periodic highlight stays static when animations are disabled', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: PeriodicHighlight(
          colors: [Colors.white],
          child: SizedBox(width: 200, height: 100),
        ),
      ),
    );

    expect(find.byType(PeriodicHighlight), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
  });
}
