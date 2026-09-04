import 'dart:io';

import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/city_map_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/screens/splash_screen.dart';
import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/bingo_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final flutterArtifacts = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent;
    await Future.wait([
      _loadFont('Sora', 'assets/fonts/Sora[wght].ttf'),
      _loadFont('Inter', 'assets/fonts/Inter[opsz,wght].ttf'),
      _loadFileFont(
        'MaterialIcons',
        File(
          '${flutterArtifacts.path}/material_fonts/'
          'materialicons-regular.otf',
        ),
      ),
    ]);
  });

  Future<void> configureViewport(
    WidgetTester tester,
    Size size, {
    bool reduceMotion = true,
  }) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pump();
    final visibleImages = find.byType(Image).evaluate().toList();
    await tester.runAsync(
      () => Future.wait([
        for (final element in visibleImages)
          precacheImage((element.widget as Image).image, element),
      ]).timeout(const Duration(seconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('warms visual assets for evidence', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Column(
          children: [
            Image.asset(AppAssets.b1nIcon),
            Image.asset(AppAssets.b1nIdeaInstruction),
            Image.asset(AppAssets.b1nMissionReady),
            Image.asset(AppAssets.b1nPortraitInstruction),
            Image.asset(AppAssets.b1nPortraitQuestion),
            Image.asset(AppAssets.b1nPortraitCelebration),
            Image.asset(AppAssets.scr4pIcon),
            Image.asset(AppAssets.scr4pDefense),
            Image.asset(AppAssets.bincoinV2),
            Image.asset(AppAssets.sceneClean),
            Image.asset(AppAssets.sceneCorrupt),
            Image.asset(AppAssets.sceneCorruptScr4p),
            Image.asset(AppAssets.sceneTransition),
            Image.asset(AppAssets.sceneConfrontation),
            Image.asset(AppAssets.totemConceptFull),
            Image.asset(AppAssets.totemSingleCutout),
            Image.asset(AppAssets.howItWorksScene),
            Image.asset(AppAssets.b3nBazaarCutout),
            Image.asset(AppAssets.b3nBazaarCounterScene),
            Image.asset(AppAssets.profileAvatarB3n),
            Image.asset(AppAssets.profileAvatarScr4p),
            Image.asset(AppAssets.profileAvatarB1nReward),
            Image.asset(AppAssets.profileAvatarB1nHero),
            Image.asset(AppAssets.rewardJuice),
            Image.asset(AppAssets.rewardPen),
            Image.asset(AppAssets.rewardCafeteriaTicket),
            Image.asset(AppAssets.rewardSurprise),
            Image.asset(AppAssets.bingopolisMap),
            Image.asset(AppAssets.corruptionClouds),
            Image.asset(AppAssets.springParkClean),
            Image.asset(AppAssets.springParkCorrupt),
            Image.asset(AppAssets.springParkCombat),
            Image.asset(AppAssets.creativeSchoolClean),
            Image.asset(AppAssets.creativeSchoolCorrupt),
            Image.asset(AppAssets.creativeSchoolCombat),
            Image.asset(AppAssets.mapLandmarkSquare),
            Image.asset(AppAssets.mapLandmarkPark),
            Image.asset(AppAssets.mapLandmarkSchool),
            Image.asset(AppAssets.bingopolisTerrainTile),
            Image.asset(AppAssets.b1nMapGuide),
            Image.asset(AppAssets.mapLandmarkSquareV2, cacheWidth: 384),
            Image.asset(AppAssets.mapLandmarkParkV2, cacheWidth: 384),
            Image.asset(AppAssets.mapLandmarkSchoolV2, cacheWidth: 384),
            Image.asset(AppAssets.mapLandmarkSquareCorruptV3, cacheWidth: 384),
            Image.asset(AppAssets.mapLandmarkParkCorruptV3, cacheWidth: 384),
            Image.asset(AppAssets.mapLandmarkSchoolCorruptV3, cacheWidth: 384),
            Image.asset(AppAssets.corruptionFogNear),
            Image.asset(AppAssets.corruptionFogMid),
            Image.asset(AppAssets.corruptionFogFar),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('captures Home at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      HomeScreen(firstName: 'Alencar', onOpenTab: (_) {}),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/home-390.png'),
    );
  });

  testWidgets('captures Splash final state at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const SplashScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/splash-390.png'),
    );
  });

  testWidgets('captures Access at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const AccessFlowScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/access-390.png'),
    );
  });

  testWidgets('captures Profile at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, ProfileScreen(onGoHome: () {}));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/profile-390.png'),
    );
  });

  testWidgets('captures Profile customization at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, ProfileScreen(onGoHome: () {}));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Personalizar perfil'));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/profile-customization-390.png'),
    );
  });

  testWidgets('captures Wallet movements at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const WalletScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/wallet-movements-390.png'),
    );
  });

  testWidgets('captures Wallet discards at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const WalletScreen());
    await tester.tap(find.text('Descartes'));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/wallet-discards-390.png'),
    );
  });

  testWidgets('captures Wallet at 430x932', (tester) async {
    await configureViewport(tester, const Size(430, 932));
    await pumpScreen(tester, const WalletScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/wallet-movements-430.png'),
    );
  });

  testWidgets('captures BinBazar at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const RewardsScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/binbazar-390.png'),
    );
  });

  testWidgets('captures BinBazar reward and confirmation at 390x844', (
    tester,
  ) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const RewardsScreen());
    await tester.ensureVisible(find.text('Suco natural'));
    await tester.tap(find.text('Suco natural'));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/binbazar-reward-390.png'),
    );

    tester
        .widget<BingoActionButton>(
          find.widgetWithText(BingoActionButton, 'Simular por 30 BinCoins'),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/binbazar-confirmation-390.png'),
    );
  });

  testWidgets('captures Ranking at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const RankingScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/ranking-390.png'),
    );
  });

  testWidgets('captures current scenario at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const CurrentScenarioScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/scenario-390.png'),
    );
  });

  testWidgets('captures BinGopolis map at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, CityMapScreen(onOpenScenario: (_, _) {}));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-map-390.png'),
    );
  });

  testWidgets('captures B1N map guide at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844), reduceMotion: false);
    await pumpScreen(tester, CityMapScreen(onOpenScenario: (_, _) {}));
    await tester.pump(const Duration(milliseconds: 620));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-guide-390.png'),
    );
  });

  testWidgets('captures animated cleanup and fog separation at 390x844', (
    tester,
  ) async {
    await configureViewport(tester, const Size(390, 844), reduceMotion: false);
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
    );
    await tester.tap(find.byTooltip('Fechar ajuda'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1250));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-cleanup-mid-390.png'),
    );

    await tester.pump(const Duration(milliseconds: 1050));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-fog-split-390.png'),
    );
  });

  testWidgets('captures discovered park map at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
    );
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-discovered-390.png'),
    );
  });

  testWidgets('captures discovered school map at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
    );
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('advance-bingopolis-journey')));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-school-390.png'),
    );
  });

  testWidgets('captures expanded map sheet at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_, _) {}),
    );
    await tester.dragFrom(const Offset(195, 730), const Offset(0, -330));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-sheet-390.png'),
    );
  });

  testWidgets('captures park combat scenario at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CurrentScenarioScreen(
        scenario: cityScenarios[1],
        progress: 0.52,
        isPilotSimulation: true,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/scenario-park-390.png'),
    );
  });

  testWidgets('captures school corrupted scenario at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CurrentScenarioScreen(
        scenario: cityScenarios[2],
        progress: 0.2,
        isPilotSimulation: true,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/scenario-school-390.png'),
    );
  });

  testWidgets('captures Impact at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const ImpactScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/impact-390.png'),
    );
  });

  testWidgets('captures Park initial impact at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      ImpactScreen(
        scenario: cityScenarios[1],
        registeredProgress: 0,
        visualProgress: 1,
        isPilotSimulation: true,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/impact-park-390.png'),
    );
  });

  testWidgets('captures School initial impact at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      ImpactScreen(
        scenario: cityScenarios[2],
        registeredProgress: 0,
        visualProgress: 1,
        isPilotSimulation: true,
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/impact-school-390.png'),
    );
  });

  testWidgets('captures Missions at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const MissionsScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/missions-390.png'),
    );
  });

  testWidgets('captures How it works at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const HowItWorksScreen());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/how-it-works-390.png'),
    );
  });

  testWidgets('captures mission detail at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const MissionDetailScreen(mission: activeMission));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/mission-detail-390.png'),
    );
  });

  testWidgets('captures SCR4P mission detail at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    final scr4pMission = missions.firstWhere(
      (mission) => mission.state == MissionState.event,
    );
    await pumpScreen(tester, MissionDetailScreen(mission: scr4pMission));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/mission-scr4p-390.png'),
    );
  });

  testWidgets('captures Totem guidance at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const TotemTrackingScreen(mission: activeMission));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/totem-guidance-390.png'),
    );
  });

  testWidgets('captures lower mission detail at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const MissionDetailScreen(mission: activeMission));
    await tester.drag(find.byType(ListView), const Offset(0, -540));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/mission-detail-lower-390.png'),
    );
  });

  testWidgets('captures lower Totem guidance at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(tester, const TotemTrackingScreen(mission: activeMission));
    await tester.drag(find.byType(ListView), const Offset(0, -880));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/totem-guidance-lower-390.png'),
    );
  });

  for (final viewport in const <(String, Size)>[
    ('390', Size(390, 844)),
    ('430', Size(430, 932)),
  ]) {
    for (final scale in const <(String, TextScaler)>[
      ('normal', TextScaler.noScaling),
      ('text-2x', TextScaler.linear(2)),
    ]) {
      if (viewport.$1 == '390' && scale.$1 == 'normal') continue;

      for (final screen in const <(String, Widget)>[
        ('ranking', RankingScreen()),
        ('missions', MissionsScreen()),
        ('how-it-works', HowItWorksScreen()),
        ('mission-detail', MissionDetailScreen(mission: activeMission)),
        ('totem-guidance', TotemTrackingScreen(mission: activeMission)),
      ]) {
        testWidgets('captures ${screen.$1} at ${viewport.$1} ${scale.$1}', (
          tester,
        ) async {
          await configureViewport(tester, viewport.$2);
          await pumpScreen(tester, screen.$2, textScaler: scale.$2);

          final scaleSuffix = scale.$1 == 'normal' ? '' : '-${scale.$1}';
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../evidence/app_v1/'
              '${screen.$1}-${viewport.$1}$scaleSuffix.png',
            ),
          );
        });
      }
    }
  }
}

Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

Future<void> _loadFileFont(String family, File file) async {
  final loader = FontLoader(family)
    ..addFont(
      file.readAsBytes().then(
        (bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
      ),
    );
  await loader.load();
}
