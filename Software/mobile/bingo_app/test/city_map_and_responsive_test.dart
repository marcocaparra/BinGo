import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/city_map_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void useViewport(
    WidgetTester tester,
    Size size, {
    bool disableAnimations = true,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: disableAnimations);
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
    bool disableAnimations = true,
  }) async {
    useViewport(tester, size, disableAnimations: disableAnimations);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
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
      expect(scenario.corruptMapLandmarkAsset, isNotEmpty);
      expect(
        scenario.corruptMapLandmarkAsset,
        isNot(scenario.mapLandmarkAsset),
      );
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
        expect(
          cardSizes.first.height,
          lessThanOrEqualTo(entry.$2 >= 1.5 ? 372 : 308),
        );

        for (final reward in rewards) {
          final action = find.byKey(ValueKey('reward-action-${reward.id}'));
          expect(action, findsOneWidget);
          expect(tester.getSize(action).width, greaterThan(120));
          final price = find.byKey(ValueKey('reward-price-${reward.cost}'));
          expect(price, findsOneWidget);
          expect(tester.getSize(price).width, greaterThan(120));
          expect(tester.getSize(price).height, greaterThanOrEqualTo(48));
          final priceBottom = tester.getBottomLeft(price).dy;
          final actionTop = tester.getTopLeft(action).dy;
          expect(actionTop - priceBottom, lessThanOrEqualTo(24));
        }
        for (final label in tester.widgetList<Text>(
          find.text('Simular resgate'),
        )) {
          expect(label.maxLines, lessThanOrEqualTo(2));
          expect(label.overflow, isNot(TextOverflow.ellipsis));
          expect(label.style?.color, Colors.white);
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
      CityMapScreen(
        isPilot: true,
        onOpenScenario: (_, _) => openedCurrent = true,
      ),
      const Size(390, 844),
    );

    expect(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bingopolis-world-backdrop')),
      findsOneWidget,
    );
    final fogImages = tester.widgetList<Image>(find.byType(Image)).where((
      image,
    ) {
      final provider = image.image;
      if (provider is! AssetImage) return false;
      return {
        AppAssets.corruptionFogNear,
        AppAssets.corruptionFogMid,
        AppAssets.corruptionFogFar,
      }.contains(provider.assetName);
    });
    expect(fogImages.length, greaterThanOrEqualTo(20));
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
    expect(viewer.boundaryMargin, EdgeInsets.zero);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('bingopolis-interactive-map')),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
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

    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scenario-marker-spring-park')));
    await tester.pump();
    expect(find.text('Parque das Nascentes'), findsAtLeastNWidgets(1));
    expect(find.text('Demonstrar Escola'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scenario-marker-creative-school')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('scenario-marker-creative-school')),
    );
    await tester.pump();
    expect(find.text('Escola Criativa'), findsAtLeastNWidgets(1));
    expect(find.text('Reiniciar demonstração'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    expect(find.text('Praça Central'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('scenario-marker-creative-school')),
      findsNothing,
    );
  });

  testWidgets('corruption storm stays static with reduced motion', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      CityMapScreen(onOpenScenario: (_, _) {}),
      const Size(390, 844),
    );
    expect(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
      findsOneWidget,
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('sector progression animates cleanup before moving the camera', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
      const Size(390, 844),
      disableAnimations: false,
    );
    await tester.pump(const Duration(milliseconds: 1100));

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('bingopolis-interactive-map')),
    );
    final initialMatrix = List<double>.of(
      viewer.transformationController!.value.storage,
    );
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('bingopolis-map-interaction-lock')),
          )
          .ignoring,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 1200));
    final progress = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .first
        .value!;
    expect(progress, greaterThan(currentScenario.restoredProgress));
    expect(progress, lessThan(1));
    expect(
      viewer.transformationController!.value.storage,
      orderedEquals(initialMatrix),
    );

    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      viewer.transformationController!.value.storage,
      isNot(orderedEquals(initialMatrix)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Parque das Nascentes'), findsAtLeastNWidgets(1));
    expect(find.text('Demonstrar Escola'), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('bingopolis-map-interaction-lock')),
          )
          .ignoring,
      isFalse,
    );
  });

  testWidgets('storm frontier remains continuous when a stage settles', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
      const Size(390, 844),
      disableAnimations: false,
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3000));

    final persistentCloud = find.byKey(
      const ValueKey('storm-bank-stage-1-cloud-0-0'),
    );
    expect(persistentCloud, findsOneWidget);
    final beforeHandoff = tester.getTopLeft(persistentCloud);

    await tester.pump(const Duration(milliseconds: 250));
    expect(persistentCloud, findsOneWidget);
    final afterHandoff = tester.getTopLeft(persistentCloud);
    expect((afterHandoff.dy - beforeHandoff.dy).abs(), lessThan(12));
    expect((afterHandoff.dx - beforeHandoff.dx).abs(), lessThan(12));
    expect(find.byKey(const ValueKey('storm-bank-retreat-0')), findsNothing);
  });

  testWidgets('map opening reports the selected visual progress', (
    tester,
  ) async {
    CityScenario? openedScenario;
    double? openedProgress;
    await pumpScreen(
      tester,
      CityMapScreen(
        isPilot: true,
        onOpenScenario: (scenario, progress) {
          openedScenario = scenario;
          openedProgress = progress;
        },
      ),
      const Size(390, 844),
    );

    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.tap(find.text('Ver cenário'));
    expect(openedScenario?.id, cityScenarios[1].id);
    expect(openedProgress, 0);

    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.tap(find.text('Ver cenário'));
    expect(openedScenario?.id, cityScenarios[2].id);
    expect(openedProgress, 0);
  });

  testWidgets('future sectors use their own zero-impact state', (tester) async {
    for (final scenario in cityScenarios.skip(1)) {
      await pumpScreen(
        tester,
        ImpactScreen(
          scenario: scenario,
          registeredProgress: scenario.progress,
          visualProgress: 1,
          isPilotSimulation: true,
        ),
        const Size(390, 844),
      );
      expect(find.text('Restauração ainda não iniciada'), findsOneWidget);
      expect(find.text('Simulação visual'), findsOneWidget);
      expect(find.textContaining(scenario.name), findsWidgets);
      final scenarioImages = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == scenario.corruptAsset,
          );
      expect(scenarioImages, isNotEmpty);
      expect(find.text('3,2 kg'), findsNothing);
      expect(tester.takeException(), isNull);
    }
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
    'city map': () => CityMapScreen(onOpenScenario: (_, _) {}),
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
