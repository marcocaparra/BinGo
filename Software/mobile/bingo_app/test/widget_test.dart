import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bingo_app/src/app.dart';
import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/data/session_wallet_controller.dart';
import 'package:bingo_app/src/screens/city_map_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/b1n_dialogue_strip.dart';
import 'package:bingo_app/src/widgets/bincoin_amount.dart';
import 'package:bingo_app/src/widgets/bingo_action_button.dart';

void main() {
  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      KeyedSubtree(key: ValueKey(size), child: const BingoApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPilot(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
  }

  testWidgets('BinBazar confirms a redemption and exposes its pickup code', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SessionWalletController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RewardsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suco natural'));
    await tester.pumpAndSettle();
    expect(find.text('Resgatar por 30 BinCoins'), findsOneWidget);
    await tester.ensureVisible(find.text('Resgatar por 30 BinCoins'));
    await tester.tap(find.text('Resgatar por 30 BinCoins'));
    await tester.pumpAndSettle();

    expect(controller.balance, 90);
    expect(find.text('Resgate confirmado'), findsOneWidget);
    expect(find.textContaining('BGO-'), findsAtLeastNWidgets(1));
  });

  for (final size in const [Size(390, 844), Size(430, 932), Size(1024, 768)]) {
    testWidgets('access flow fits ${size.width}x${size.height}', (
      WidgetTester tester,
    ) async {
      await pumpAtSize(tester, size);

      expect(find.text('Criar meu PIN'), findsOneWidget);
      expect(find.text('Já tenho PIN'), findsOneWidget);
      expect(find.text('Entrar no modo piloto'), findsOneWidget);
    });
  }

  testWidgets('can enter the app on a compact phone viewport', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    expect(find.text('Criar meu PIN'), findsOneWidget);

    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();

    expect(find.text('Olá, Marco!'), findsOneWidget);
    expect(find.text('Praça Central'), findsOneWidget);
  });

  testWidgets('home presents one clear path', (WidgetTester tester) async {
    for (final size in const [Size(390, 844), Size(430, 932)]) {
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await pumpAtSize(tester, size);
      await enterPilot(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(find.text('Praça Central'), findsOneWidget);
      expect(find.text('Missão ativa'), findsOneWidget);
      expect(find.text('2 descartes para o próximo setor'), findsOneWidget);
      expect(find.text('Começar no Totem'), findsOneWidget);
      expect(find.text('Como funciona o BinGo'), findsOneWidget);
      expect(find.byTooltip('Como funciona'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Como funciona o BinGo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Como funciona o BinGo'));
      await tester.pumpAndSettle();

      expect(find.text('1. Prepare com segurança'), findsOneWidget);
      expect(find.text('2. Use o Totem'), findsOneWidget);
      expect(find.text('3. Acompanhe no app'), findsOneWidget);
      expect(find.text('Segurança primeiro'), findsOneWidget);
      expect(find.text('Resultado pessoal'), findsOneWidget);
      expect(find.text('Resultado coletivo'), findsOneWidget);
      expect(find.text('Começar no Totem'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Como funciona'), findsNothing);
      expect(find.text('Como funciona o BinGo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    testWidgets('home keeps the Totem CTA visible and tappable at 2x on '
        '${size.width}x${size.height}', (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await pumpAtSize(tester, size);
      await enterPilot(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      final cta = find.widgetWithText(BingoActionButton, 'Começar no Totem');
      final ctaRect = tester.getRect(cta);

      expect(cta, findsOneWidget);
      expect(ctaRect.top, greaterThanOrEqualTo(0));
      expect(
        ctaRect.bottom,
        lessThanOrEqualTo(size.height),
        reason: 'CTA rect: $ctaRect',
      );
      expect(cta.hitTestable(), findsOneWidget, reason: 'CTA rect: $ctaRect');
      expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));
      expect(find.text('Ver detalhes da missão'), findsNothing);

      final scr4p = find.text('Alerta SCR4P');
      final impact = find.text('Ver impacto da turma');
      final help = find.text('Como funciona o BinGo');
      expect(scr4p, findsOneWidget);
      expect(impact, findsOneWidget);
      expect(help, findsOneWidget);
      expect(tester.getTopLeft(cta).dy, lessThan(tester.getTopLeft(scr4p).dy));
      expect(
        tester.getTopLeft(scr4p).dy,
        lessThan(tester.getTopLeft(impact).dy),
      );
      expect(
        tester.getTopLeft(impact).dy,
        lessThan(tester.getTopLeft(help).dy),
      );

      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.text('No Totem'), findsOneWidget);
    });
  }

  testWidgets('how it works steps keep visual and semantic order', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAtSize(tester, const Size(390, 844));
    await enterPilot(tester);
    await tester.ensureVisible(find.text('Como funciona o BinGo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Como funciona o BinGo'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.byIcon(Icons.precision_manufacturing_outlined), findsOneWidget);
    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Etapa 1 de 3. Prepare com segurança. '
        'Separe um eletrônico pequeno, sem uso, seco e autorizado.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Etapa 2 de 3. Use o Totem. '
        'Escolha sua turma e siga as instruções do equipamento físico.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Etapa 3 de 3. Acompanhe no app. Depois da validação, consulte '
        'BinCoins, pontos e a recuperação da cidade.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('home reaches Totem guidance without creating another flow', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Começar no Totem'));
    await tester.tap(find.text('Começar no Totem'));
    await tester.pumpAndSettle();

    expect(find.text('No Totem'), findsOneWidget);
    expect(find.text('Seu caminho no Totem'), findsOneWidget);
    expect(find.text('Resultado no app'), findsOneWidget);
    expect(
      find.text('Após o Totem validar, BinCoins e pontos aparecem no app.'),
      findsOneWidget,
    );
    expect(find.text('Validação no app'), findsNothing);
    expect(find.byType(B1nDialogueStrip), findsOneWidget);

    expect(find.text('Depois da validação'), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(find.byIcon(Icons.auto_graph_outlined), findsOneWidget);
    expect(
      find.widgetWithText(BingoActionButton, 'Ver impacto da turma'),
      findsNothing,
    );
  });

  testWidgets('scr4p alert opens explanation from home', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Alerta SCR4P'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerta SCR4P'));
    await tester.pumpAndSettle();

    expect(find.text('Quem é SCR4P?'), findsOneWidget);
    expect(find.text('Ver defesa ativa'), findsOneWidget);
  });

  testWidgets('wallet, ranking and profile refinements render on phone', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carteira'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir BinBazar'));
    await tester.pumpAndSettle();

    expect(find.text('Tio B3N cuida do balcão'), findsOneWidget);
    expect(find.text('Suco natural'), findsOneWidget);
    expect(find.text('Ticket cantina'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.text('Turmas da Praça'), findsOneWidget);
    expect(find.text('BinGópolis · 3 setores'), findsOneWidget);
    expect(find.text('Explorar BinGópolis'), findsOneWidget);
    expect(find.text('12 dias'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('760'), findsOneWidget);
    expect(find.text('Pontos pessoais'), findsOneWidget);
    expect(find.text('Pontos da turma'), findsOneWidget);
    expect(find.text('BinCoins'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardião'));
    expect(find.text('Herói'), findsOneWidget);
  });

  testWidgets(
    'wallet presents BinCoin balance, history verbs and focused bazaar',
    (WidgetTester tester) async {
      await pumpAtSize(tester, const Size(390, 844));
      await enterPilot(tester);

      await tester.tap(find.text('Carteira'));
      await tester.pumpAndSettle();

      expect(find.text('Saldo disponível'), findsOneWidget);
      expect(find.text('3 recompensas disponíveis'), findsOneWidget);
      expect(find.text('Ganhou'), findsNWidgets(2));
      expect(find.text('Usou'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(
        tester
            .widgetList<Icon>(find.byIcon(Icons.add_rounded))
            .every((icon) => icon.color == AppColors.green),
        isTrue,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.remove_rounded)).color,
        AppColors.danger,
      );
      expect(find.byType(BinCoinIcon), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byType(BinCoinAmount),
          matching: find.byType(BinCoinIcon),
        ),
        findsNWidgets(4),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('wallet-tab-extrato')),
                matching: find.text('Extrato'),
              ),
            )
            .style
            ?.color,
        AppColors.green,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('wallet-tab-descartes')),
                matching: find.text('Descartes'),
              ),
            )
            .style
            ?.color,
        AppColors.textMuted,
      );

      await tester.tap(find.text('Descartes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('wallet-tab-extrato')),
                matching: find.text('Extrato'),
              ),
            )
            .style
            ?.color,
        AppColors.textMuted,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('wallet-tab-descartes')),
                matching: find.text('Descartes'),
              ),
            )
            .style
            ?.color,
        AppColors.blue,
      );
      expect(find.text('Mouse sem uso'), findsOneWidget);
      expect(find.text('Cabo USB'), findsOneWidget);
      expect(find.text('Fone de ouvido'), findsOneWidget);
      expect(find.text('Validado no Totem'), findsNWidgets(3));
      expect(find.text('+25 pts turma'), findsOneWidget);

      await tester.tap(find.text('Abrir BinBazar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Troque BinCoins'), findsAtLeastNWidgets(1));
      expect(find.text('Tio B3N cuida do balcão'), findsOneWidget);
      expect(find.bySemanticsLabel('120 BinCoins'), findsOneWidget);
      expect(find.text('Resgatar'), findsNWidgets(3));
      expect(find.text('Faltam 60'), findsOneWidget);
    },
  );

  testWidgets('wallet exposes empty states for both history sections', (
    WidgetTester tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const WalletScreen(transactions: [], discards: []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma movimentação'), findsOneWidget);
    await tester.tap(find.text('Descartes'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum descarte validado'), findsOneWidget);
  });

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    testWidgets('wallet remains usable at 2x on ${size.width}x${size.height}', (
      WidgetTester tester,
    ) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: WalletScreen(),
          ),
        ),
      );
      await tester.pump();

      final extrato = tester.widget<Text>(find.text('Extrato'));
      final descartes = tester.widget<Text>(find.text('Descartes'));

      expect(extrato.maxLines, 1);
      expect(extrato.softWrap, isFalse);
      expect(descartes.maxLines, 1);
      expect(descartes.softWrap, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('main simulated sections expose useful empty states', (
    WidgetTester tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    Future<void> expectEmpty(Widget screen, String title) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: screen),
      );
      await tester.pump();
      expect(find.text(title), findsOneWidget);
    }

    await expectEmpty(
      const RewardsScreen(items: []),
      'BinBazar sem recompensas',
    );
    await expectEmpty(
      const MissionsScreen(items: []),
      'Nenhuma missão disponível',
    );
    await expectEmpty(const RankingScreen(rows: []), 'Ranking ainda sem dados');
  });

  testWidgets(
    'missions prioritize stateful progress without opening the Totem',
    (WidgetTester tester) async {
      await pumpAtSize(tester, const Size(390, 844));
      await enterPilot(tester);

      await tester.tap(find.text('Missões'));
      await tester.pumpAndSettle();

      expect(find.text('Missão ativa'), findsOneWidget);
      expect(find.text('Evento em destaque'), findsOneWidget);
      expect(find.text('EVENTO ATIVO'), findsOneWidget);
      expect(find.text('Concluída'), findsOneWidget);
      expect(find.text('Em breve'), findsOneWidget);
      expect(find.text('Outras missões'), findsOneWidget);
      expect(find.text('3 de 3 descartes concluídos'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);

      await tester.tap(find.text('Recicle 1 item'));
      await tester.pumpAndSettle();

      expect(find.text('Objetivo'), findsOneWidget);
      expect(find.text('Segurança antes dos pontos'), findsOneWidget);
      expect(find.text('Como completar'), findsOneWidget);
      expect(find.text('Missão rápida'), findsOneWidget);
      expect(find.text('+10 BinCoins'), findsOneWidget);
      expect(find.byType(B1nDialogueStrip), findsOneWidget);
      expect(find.text('Ir ao Totem'), findsNothing);
      expect(find.text('Começar no Totem'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Defesa contra SCR4P'));
      await tester.tap(find.text('Defesa contra SCR4P'));
      await tester.pumpAndSettle();

      expect(find.text('Missão'), findsOneWidget);
      expect(find.text('Defesa especial'), findsOneWidget);
      expect(find.text('SCR4P ainda controla 58% do setor'), findsOneWidget);
      expect(find.text('Ver objetivo da defesa'), findsNothing);
      expect(find.text('Ir ao Totem'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Missões'), findsOneWidget);
    },
  );

  testWidgets(
    'ranking leads with class distance and connects scenario to impact',
    (WidgetTester tester) async {
      await pumpAtSize(tester, const Size(390, 844));
      await enterPilot(tester);

      await tester.tap(find.text('Ranking'));
      await tester.pumpAndSettle();

      expect(find.text('Sua turma · 9ºA'), findsOneWidget);
      expect(find.text('760 pts'), findsOneWidget);
      expect(find.text('Faltam 50 pts para entrar no top 3'), findsOneWidget);
      final mapImages = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName ==
                    AppAssets.bingopolisMap,
          );
      expect(mapImages, hasLength(1));
      expect(
        tester.getTopLeft(find.text('Sua turma · 9ºA')).dy,
        lessThan(tester.getTopLeft(find.text('Turmas da Praça')).dy),
      );

      await tester.ensureVisible(find.text('Explorar BinGópolis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explorar BinGópolis'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(CityMapScreen), findsOneWidget);
      expect(find.text('Próximo setor'), findsOneWidget);
      expect(find.text('Escola Criativa'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('scenario-marker-central-square')),
      );
      await tester.tap(find.text('Ver cenário'));
      await tester.pumpAndSettle();
      expect(find.text('Régua de restauração'), findsOneWidget);
      expect(find.text('68% restaurada'), findsOneWidget);
      expect(find.text('2'), findsAtLeastNWidgets(1));
      expect(find.text('12'), findsAtLeastNWidgets(1));

      await tester.ensureVisible(find.text('Ver impacto da turma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver impacto da turma'));
      await tester.pumpAndSettle();

      expect(find.text('Antes'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);
      expect(find.text('68% restaurada'), findsOneWidget);
      expect(find.text('3,2 kg'), findsOneWidget);
      expect(find.text('Próxima transformação'), findsOneWidget);
      expect(find.text('Ver evolução da Praça'), findsNothing);
      expect(find.text('História'), findsNothing);
    },
  );

  testWidgets('mission visuals follow each mission theme', (
    WidgetTester tester,
  ) async {
    Future<void> expectMissionImage(Mission mission) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MissionDetailScreen(mission: mission),
        ),
      );
      await tester.pump();

      final themedImages = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == mission.image,
          );
      expect(themedImages, hasLength(1));
      expect(find.byType(B1nDialogueStrip), findsOneWidget);
      expect(
        tester.widget<B1nDialogueStrip>(find.byType(B1nDialogueStrip)).tone,
        mission.state == MissionState.event ? AppColors.blue : mission.color,
      );
      final expectedDialogueAsset = mission.state == MissionState.event
          ? AppAssets.b1nPortraitQuestion
          : AppAssets.b1nPortraitInstruction;
      final b1nImages = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == expectedDialogueAsset,
          );
      expect(b1nImages, hasLength(1));
      expect(tester.takeException(), isNull);
    }

    await expectMissionImage(activeMission);
    await expectMissionImage(missions[1]);
    await expectMissionImage(missions[2]);
  });

  testWidgets('Totem is physical, stateful and does not reuse mission scenery', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const TotemTrackingScreen(mission: activeMission),
      ),
    );
    await tester.pump();

    int countAsset(String asset) {
      return tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == asset,
          )
          .length;
    }

    expect(countAsset(AppAssets.totemConceptFull), 1);
    expect(countAsset(activeMission.image), 0);
    expect(countAsset(AppAssets.b1nPortraitCelebration), 1);
    for (final state in const <(String, Color)>[
      (
        'Concluído: Item preparado. Eletrônico sem uso, autorizado, seco e sem risco.',
        AppColors.green,
      ),
      (
        'Etapa atual: Use o Totem. Escolha sua turma e siga a tela do equipamento.',
        AppColors.blue,
      ),
      (
        'Próxima etapa: Resultado no app. Após o Totem validar, BinCoins e pontos aparecem no app.',
        AppColors.warning,
      ),
    ]) {
      final step = find.bySemanticsLabel(state.$1);
      expect(step, findsOneWidget);
      final containers = tester.widgetList<Container>(
        find.descendant(of: step, matching: find.byType(Container)),
      );
      expect(
        containers.any(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).color == state.$2,
        ),
        isTrue,
      );
    }
    expect(find.text('Pode levar'), findsOneWidget);
    expect(find.text('Peça ajuda'), findsOneWidget);
    expect(find.text('Não toque'), findsOneWidget);
    expect(find.text('Validação no app'), findsNothing);
    expect(find.text('Depois da validação'), findsOneWidget);
    expect(
      find.widgetWithText(BingoActionButton, 'Ver impacto da turma'),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('SCR4P explanation uses purple numbered indicators', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));
    await enterPilot(tester);

    await tester.ensureVisible(find.text('Alerta SCR4P'));
    await tester.tap(find.text('Alerta SCR4P'));
    await tester.pumpAndSettle();

    for (final title in const [
      'Ele ataca cenários',
      'A turma limpa setores',
      'Quem ajuda mais ganha mais',
    ]) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(Row),
      );
      final circles = tester.widgetList<Container>(
        find.descendant(of: row, matching: find.byType(Container)),
      );
      expect(
        circles.any(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).shape ==
                  BoxShape.circle &&
              (container.decoration! as BoxDecoration).color == AppColors.scr4p,
        ),
        isTrue,
      );
    }
  });

  for (final size in const [Size(390, 844), Size(430, 932)]) {
    for (final screen in const <(String, Widget)>[
      ('ranking', RankingScreen()),
      ('scenario', CurrentScenarioScreen()),
      ('impact', ImpactScreen()),
      ('mission detail', MissionDetailScreen(mission: activeMission)),
      ('totem', TotemTrackingScreen(mission: activeMission)),
    ]) {
      testWidgets(
        '${screen.$1} supports 2x text at ${size.width}x${size.height}',
        (WidgetTester tester) async {
          tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(
            tester
                .binding
                .platformDispatcher
                .clearAccessibilityFeaturesTestValue,
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: screen.$2,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
