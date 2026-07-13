import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bingo_app/src/app.dart';

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

    await tester.pumpWidget(const BingoApp());
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
  });

  testWidgets('scr4p alert opens explanation from home', (
    WidgetTester tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844));

    await tester.tap(find.text('Começar missão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar no modo piloto'));
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
    expect(find.text('Pts pessoais'), findsOneWidget);
    expect(find.textContaining('5 descartes validados'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardião'));
    expect(find.text('Herói'), findsOneWidget);
  });
}
