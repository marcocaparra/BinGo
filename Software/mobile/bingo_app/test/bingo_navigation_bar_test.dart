import 'package:bingo_app/src/widgets/bingo_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps destinations fixed while selection changes', (
    WidgetTester tester,
  ) async {
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: BingoNavigationBar(
              selectedIndex: selected,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    const labels = ['Início', 'Carteira', 'Missões', 'Ranking', 'Perfil'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Perfil'));
    await tester.pump();

    expect(selected, 4);
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const Key('bingo-nav-indicator-4')), findsOneWidget);
  });
}
