import 'dart:io';

import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/screens/city_map_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
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

  Future<void> configureViewport(WidgetTester tester, Size size) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
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
    await tester.pump(const Duration(seconds: 1));
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
    await pumpScreen(tester, CityMapScreen(onOpenScenario: (_) {}));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-map-390.png'),
    );
  });

  testWidgets('captures discovered park map at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CityMapScreen(isPilot: true, onOpenScenario: (_) {}),
    );
    await tester.tap(find.text('Simular descoberta'));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../evidence/app_v1/bingopolis-discovered-390.png'),
    );
  });

  testWidgets('captures park combat scenario at 390x844', (tester) async {
    await configureViewport(tester, const Size(390, 844));
    await pumpScreen(
      tester,
      CurrentScenarioScreen(scenario: cityScenarios[1], progress: 0.52),
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
      CurrentScenarioScreen(scenario: cityScenarios[2], progress: 0.2),
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
