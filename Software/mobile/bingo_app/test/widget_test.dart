import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bingo_app/src/app.dart';
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
    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(430, 932), Size(1024, 768)]) {
    testWidgets('onboarding fits ${size.width}x${size.height}', (
      WidgetTester tester,
    ) async {
      await pumpAtSize(tester, size);

      expect(find.text('Ajude BinGópolis'), findsOneWidget);
      expect(find.text('Começar missão'), findsOneWidget);
      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Vá ao Totem'), findsOneWidget);
      expect(find.text('Valide'), findsOneWidget);
      expect(find.text('Impacte'), findsOneWidget);
    });
  }

  testWidgets('can enter the app on a compact phone viewport', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();

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

      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Vá ao Totem'), findsOneWidget);
      expect(find.text('Valide'), findsOneWidget);
      expect(find.text('Gere impacto'), findsOneWidget);
      expect(find.text('Segurança primeiro'), findsOneWidget);
      expect(find.text('Pontos e recompensas'), findsOneWidget);
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

  testWidgets('icon steps keep their visual and semantic position', (
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
    expect(find.text('1'), findsOneWidget);
    expect(find.bySemanticsLabel('1 de 4'), findsOneWidget);
    expect(find.bySemanticsLabel('2 de 4'), findsOneWidget);
    expect(find.bySemanticsLabel('3 de 4'), findsOneWidget);
    expect(find.bySemanticsLabel('4 de 4'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('mission reaches totem guidance and impact', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Começar no Totem'));
    await tester.tap(find.text('Começar no Totem'));
    await tester.pumpAndSettle();

    expect(find.text('No Totem'), findsOneWidget);
    expect(find.text('BinGo recompensa responsabilidade'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ver impacto'));
    await tester.tap(find.text('Ver impacto'));
    await tester.pumpAndSettle();

    expect(find.text('Impacto'), findsOneWidget);
    expect(find.text('Setor liberado!'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Ver impacto'), findsOneWidget);
    expect(find.text('Impacto'), findsNothing);
  });

  testWidgets('scr4p alert opens explanation from home', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carteira'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir BinBazar'));
    await tester.pumpAndSettle();

    expect(find.text('Tio B3N cuida do balcão'), findsOneWidget);
    expect(find.text('Suco natural'), findsOneWidget);
    expect(find.text('Ticket cantina'), findsOneWidget);

    Navigator.of(tester.element(find.text('BinBazar'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.text('Top turmas da Praça'), findsOneWidget);
    expect(find.text('Cenário atual: Praça Central'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Prêmios do ciclo'));
    expect(find.textContaining('Prêmios do ciclo'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('760'), findsOneWidget);
    expect(find.text('Pontos pessoais'), findsOneWidget);
    expect(find.text('Pontos da turma'), findsOneWidget);
    expect(find.text('BinCoins'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardião'));
    expect(find.text('Herói'), findsOneWidget);
  });
}
