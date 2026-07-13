import 'dart:ui' show Tristate;

import 'package:bingo_app/src/widgets/bingo_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = ['Início', 'Carteira', 'Missões', 'Ranking', 'Perfil'];

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

  testWidgets('exposes destinations in circular visual order', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpNavigationBar(tester, selectedIndex: 3, onSelected: (_) {});

    final orderedLabels = <String>[];
    void collectLabels(SemanticsNode node) {
      if (labels.contains(node.label)) {
        orderedLabels.add(node.label);
      }
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        collectLabels(child);
      }
    }

    collectLabels(
      RendererBinding
          .instance
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );

    expect(orderedLabels, [
      'Carteira',
      'Missões',
      'Ranking',
      'Perfil',
      'Início',
    ]);
    for (var index = 0; index < labels.length; index++) {
      final node = tester.getSemantics(
        find.byKey(Key('bingo-nav-destination-$index')),
      );
      expect(
        node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue,
        labels[index] == 'Ranking',
      );
    }
    semantics.dispose();
  });

  testWidgets('keeps five 48dp targets at widths below 240dp', (tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await pumpNavigationBar(tester, selectedIndex: 0, onSelected: (_) {});

    for (var index = 0; index < 5; index++) {
      final destination = find.byKey(Key('bingo-nav-destination-$index'));
      expect(destination, findsOneWidget);
      expect(tester.getSize(destination).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(destination).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.bySemanticsLabel(labels[index])).label,
        labels[index],
      );
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final width in [390.0, 430.0]) {
    testWidgets('fills $width dp without shrinking navigation targets', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpNavigationBar(tester, selectedIndex: 0, onSelected: (_) {});
      for (var index = 0; index < 5; index++) {
        final destination = find.byKey(Key('bingo-nav-destination-$index'));
        expect(tester.getSize(destination).width, width / 5);
        expect(tester.getSize(destination).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('animates between selections in the same navigation widget', (
    tester,
  ) async {
    var selectedIndex = 0;
    late StateSetter updateState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;
            return Scaffold(
              bottomNavigationBar: BingoNavigationBar(
                selectedIndex: selectedIndex,
                onSelected: (_) {},
              ),
            );
          },
        ),
      ),
    );

    final destination = find.byKey(const Key('bingo-nav-destination-1'));
    final start = tester.getCenter(destination).dx;
    updateState(() => selectedIndex = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));

    final middle = tester.getCenter(destination).dx;
    expect(middle, lessThan(start));
    expect(middle, greaterThan(400));
    for (var index = 0; index < 5; index++) {
      expect(find.byKey(Key('bingo-nav-destination-$index')), findsOneWidget);
    }

    await tester.pumpAndSettle();
    expect(tester.getCenter(destination).dx, 400);
    expect(
      find.descendant(
        of: find.byKey(const Key('bingo-nav-slot-2')),
        matching: destination,
      ),
      findsOneWidget,
    );
  });
}
