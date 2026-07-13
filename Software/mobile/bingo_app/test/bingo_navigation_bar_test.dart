import 'package:bingo_app/src/widgets/bingo_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNavigationBar(
    WidgetTester tester, {
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            bottomNavigationBar: BingoNavigationBar(
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  for (var selectedIndex = 0; selectedIndex < 5; selectedIndex++) {
    testWidgets('centers logical destination $selectedIndex in slot 2', (
      tester,
    ) async {
      await pumpNavigationBar(
        tester,
        selectedIndex: selectedIndex,
        onSelected: (_) {},
      );

      final centerSlot = find.byKey(const Key('bingo-nav-slot-2'));
      expect(centerSlot, findsOneWidget);
      expect(
        find.descendant(
          of: centerSlot,
          matching: find.byKey(Key('bingo-nav-destination-$selectedIndex')),
        ),
        findsOneWidget,
      );

      for (var originalIndex = 0; originalIndex < 5; originalIndex++) {
        expect(
          find.byKey(Key('bingo-nav-destination-$originalIndex')),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'reports the original logical index when a destination is tapped',
    (tester) async {
      int? tappedIndex;
      await pumpNavigationBar(
        tester,
        selectedIndex: 3,
        onSelected: (value) => tappedIndex = value,
      );

      await tester.tap(find.byKey(const Key('bingo-nav-destination-1')));

      expect(tappedIndex, 1);
    },
  );

  testWidgets('uses zero duration when animations are disabled', (
    tester,
  ) async {
    await pumpNavigationBar(
      tester,
      selectedIndex: 2,
      onSelected: (_) {},
      disableAnimations: true,
    );

    final positionedAnimations = tester.widgetList<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    final slideAnimations = tester.widgetList<AnimatedSlide>(
      find.byType(AnimatedSlide),
    );
    final scaleAnimations = tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    );

    expect(positionedAnimations, hasLength(6));
    expect(slideAnimations, hasLength(5));
    expect(scaleAnimations, hasLength(5));
    expect(
      [
        ...positionedAnimations,
        ...slideAnimations,
        ...scaleAnimations,
      ].map((animation) => animation.duration),
      everyElement(Duration.zero),
    );
  });
}
