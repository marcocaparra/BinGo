import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/city_map_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double textScale = 1,
  }) async {
    useViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: screen,
        ),
      ),
    );
    await tester.pump();
  }

  test('BinGópolis has exactly three sequential city sectors', () {
    expect(cityScenarios, hasLength(3));
    expect(cityScenarios.map((scenario) => scenario.name), [
      'Praça Central',
      'Parque das Nascentes',
      'Escola Criativa',
    ]);
    expect(cityScenarios.first.state, ScenarioState.active);
    expect(cityScenarios.first.progress, currentScenario.restoredProgress);
    expect(
      cityScenarios
          .skip(1)
          .every((scenario) => scenario.state == ScenarioState.locked),
      isTrue,
    );
    expect(currentScenario.nextSectorName, 'Parque das Nascentes');
  });

  test('each sector owns distinct assets across all visual phases', () {
    for (final scenario in cityScenarios) {
      expect(scenario.phaseFor(0.34), ScenarioVisualPhase.corrupted);
      expect(scenario.phaseFor(0.35), ScenarioVisualPhase.combat);
      expect(scenario.phaseFor(0.84), ScenarioVisualPhase.combat);
      expect(scenario.phaseFor(0.85), ScenarioVisualPhase.restored);
      expect({
        scenario.corruptAsset,
        scenario.combatAsset,
        scenario.cleanAsset,
      }, hasLength(3));
      expect(scenario.mapLandmarkAsset, isNotEmpty);
    }
  });

  for (final entry in const [
    (Size(360, 800), 1.0),
    (Size(390, 844), 1.0),
    (Size(430, 932), 1.0),
    (Size(360, 800), 2.0),
    (Size(390, 844), 2.0),
    (Size(430, 932), 2.0),
  ]) {
    testWidgets(
      'BinBazar cards stay equal at ${entry.$1.width} text ${entry.$2}x',
      (tester) async {
        await pumpScreen(
          tester,
          const RewardsScreen(),
          entry.$1,
          textScale: entry.$2,
        );

        final cardSizes = <Size>[
          for (final reward in rewards)
            tester.getSize(find.byKey(ValueKey('reward-card-${reward.id}'))),
        ];
        expect(cardSizes.map((size) => size.height).toSet(), hasLength(1));
        expect(cardSizes.map((size) => size.width).toSet(), hasLength(1));

        for (final reward in rewards) {
          final action = find.byKey(ValueKey('reward-action-${reward.id}'));
          expect(action, findsOneWidget);
          expect(tester.getSize(action).width, greaterThan(120));
        }
        for (final label in tester.widgetList<Text>(find.text('Resgatar'))) {
          expect(label.maxLines, 1);
          expect(label.softWrap, isFalse);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('map supports pan, recenter and contextual scenario opening', (
    tester,
  ) async {
    var openedCurrent = false;
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_) => openedCurrent = true),
      const Size(390, 844),
    );

    expect(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scenario-marker-central-square')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scenario-marker-spring-park')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scenario-marker-creative-school')),
      findsNothing,
    );
    expect(find.text('Escola Criativa'), findsNothing);

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
    );
    final initialMatrix = List<double>.of(
      viewer.transformationController!.value.storage,
    );
    await tester.drag(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
      const Offset(-70, 45),
    );
    await tester.pump();
    expect(
      viewer.transformationController!.value.storage,
      isNot(initialMatrix),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('recenter-bingopolis-map')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('recenter-bingopolis-map')));
    await tester.pump();
    expect(
      viewer.transformationController!.value.storage,
      orderedEquals(initialMatrix),
    );

    await tester.tap(
      find.byKey(const ValueKey('scenario-marker-central-square')),
    );
    expect(openedCurrent, isFalse);
    await tester.tap(find.text('Ver cenário'));
    expect(openedCurrent, isTrue);

    await tester.tap(find.text('Simular descoberta'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scenario-marker-spring-park')));
    await tester.pump();
    expect(find.text('Parque das Nascentes'), findsAtLeastNWidgets(1));
    expect(find.text('Reiniciar mapa'), findsOneWidget);
    expect(find.text('Escola Criativa'), findsNothing);
  });

  testWidgets('corruption storm stays static with reduced motion', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      CityMapScreen(onOpenScenario: (_) {}),
      const Size(390, 844),
    );
    expect(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
      findsOneWidget,
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  final screens = <String, Widget Function()>{
    'access': () => const AccessFlowScreen(),
    'home': () => HomeScreen(firstName: 'Alencar', onOpenTab: (_) {}),
    'wallet': () => const WalletScreen(),
    'bazaar': () => const RewardsScreen(),
    'missions': () => const MissionsScreen(),
    'mission detail': () => const MissionDetailScreen(mission: activeMission),
    'totem': () => const TotemTrackingScreen(mission: activeMission),
    'ranking': () => const RankingScreen(),
    'city map': () => CityMapScreen(onOpenScenario: (_) {}),
    'scenario': () => const CurrentScenarioScreen(),
    'impact': () => const ImpactScreen(),
    'how it works': () => const HowItWorksScreen(),
    'profile': () => ProfileScreen(onGoHome: () {}),
  };

  for (final size in const [Size(360, 800), Size(390, 844), Size(430, 932)]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets(
        'all main screens fit ${size.width}x${size.height} at ${textScale}x',
        (tester) async {
          for (final entry in screens.entries) {
            await pumpScreen(tester, entry.value(), size, textScale: textScale);
            final pages = find.byType(ListView);
            if (pages.evaluate().isNotEmpty) {
              await tester.drag(
                pages.first,
                const Offset(0, -4000),
                warnIfMissed: false,
              );
              await tester.pump();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key} overflowed at $size and ${textScale}x',
            );
          }
        },
      );
    }
  }
}
