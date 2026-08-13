import 'package:bingo_app/src/widgets/bingo_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary action exposes a tappable button and calls its handler', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BingoActionButton(
            label: 'Criar meu PIN',
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('Criar meu PIN'), findsOneWidget);
    await tester.tap(find.text('Criar meu PIN'));

    expect(taps, 1);
  });

  testWidgets('disabled action does not react to taps', (WidgetTester tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BingoActionButton(
            label: 'Continuar',
            onPressed: null,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continuar'));

    expect(taps, 0);
  });

  testWidgets('primary action uses a moving energy highlight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BingoActionButton(label: 'Continuar', onPressed: () {}),
        ),
      ),
    );

    expect(find.byKey(const Key('bingo-action-energy-highlight')), findsOneWidget);
    expect(find.byKey(const Key('bingo-action-energy-slide')), findsOneWidget);
  });

  testWidgets('reduced motion keeps a static highlight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: BingoActionButton(label: 'Continuar', onPressed: () {}),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('bingo-action-energy-highlight')), findsOneWidget);
    expect(find.byKey(const Key('bingo-action-energy-slide')), findsNothing);
  });
}
