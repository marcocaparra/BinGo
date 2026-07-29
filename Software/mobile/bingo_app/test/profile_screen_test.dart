import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/change_pin_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/bincoin_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileRepository implements ProfileRepository {
  StudentProfile? profile = const StudentProfile(
    school: 'ENIAC',
    identifier: 'Marco Caparra',
  );
  String pin = '4826';

  @override
  Future<void> deleteProfile() async => profile = null;

  @override
  Future<bool> hasProfile() async => profile != null;

  @override
  Future<StudentProfile?> loadProfile() async => profile;

  @override
  Future<void> save({
    required StudentProfile profile,
    required String pin,
  }) async {
    this.profile = profile;
    this.pin = pin;
  }

  @override
  Future<bool> verify({
    required String school,
    required String identifier,
    required String pin,
  }) async => this.pin == pin;

  @override
  Future<bool> resetPin({
    required String school,
    required String identifier,
    required String newPin,
  }) async {
    if (profile?.school != school || profile?.identifier != identifier) {
      return false;
    }
    pin = newPin;
    return true;
  }
}

void main() {
  void reduceMotion(WidgetTester tester) {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
  }

  testWidgets('profile separates resources and shows the level path', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(repository: _ProfileRepository(), onGoHome: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pontos pessoais'), findsOneWidget);
    expect(find.text('Pontos da turma'), findsOneWidget);
    expect(find.text('BinCoins'), findsOneWidget);
    for (final level in [
      'Aprendiz',
      'Explorador',
      'Restaurador',
      'Guardião',
      'Herói',
    ]) {
      expect(find.text(level), findsOneWidget);
    }
  });

  for (final viewport in <Size>[const Size(390, 844), const Size(430, 932)]) {
    testWidgets(
      'profile resources stay compact at ${viewport.width.toInt()} with text scale 2',
      (WidgetTester tester) async {
        reduceMotion(tester);
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              repository: _ProfileRepository(),
              onGoHome: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final resourceKeys = <String>[
          'profile-resource-personal',
          'profile-resource-class',
          'profile-resource-bincoins',
        ];
        for (final key in resourceKeys) {
          final tile = find.byKey(ValueKey<String>(key));
          expect(tile, findsOneWidget);
          expect(tester.getSize(tile).height, inInclusiveRange(112, 120));
        }

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.bolt_rounded), findsNothing);

        final coinIcon = find.descendant(
          of: find.byKey(const ValueKey<String>('profile-resource-bincoins')),
          matching: find.byType(BinCoinIcon),
        );
        expect(coinIcon, findsOneWidget);
        expect(tester.getSize(coinIcon), const Size.square(26));
        final coinAmount = find.descendant(
          of: find.byKey(const ValueKey<String>('profile-resource-bincoins')),
          matching: find.byType(BinCoinAmount),
        );
        expect(coinAmount, findsOneWidget);
        expect(tester.widget<BinCoinAmount>(coinAmount).showIcon, isFalse);

        final leadingTops = <double>[
          tester.getTopLeft(find.byIcon(Icons.person_rounded)).dy,
          tester.getTopLeft(find.byIcon(Icons.groups_rounded)).dy,
          tester.getTopLeft(coinIcon).dy,
        ];
        final valueTops = <double>[
          tester.getTopLeft(find.text('760')).dy,
          tester.getTopLeft(find.text('1.190')).dy,
          tester.getTopLeft(find.text('120')).dy,
        ];
        final labelTops = <double>[
          tester.getTopLeft(find.text('Pontos pessoais')).dy,
          tester.getTopLeft(find.text('Pontos da turma')).dy,
          tester.getTopLeft(find.text('BinCoins')).dy,
        ];
        for (final tops in [leadingTops, valueTops, labelTops]) {
          expect(tops.toSet(), hasLength(1));
        }

        for (final label in [
          'Pontos pessoais',
          'Pontos da turma',
          'BinCoins',
        ]) {
          final text = tester.widget<Text>(find.text(label));
          expect(text.maxLines, 2);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.style?.fontSize ?? 11, greaterThanOrEqualTo(10));
        }
        expect(find.bySemanticsLabel('120 BinCoins'), findsOneWidget);
        expect(find.bySemanticsLabel('BinCoins'), findsNothing);
      },
    );
  }

  testWidgets('profile opens PIN redefinition', (WidgetTester tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(repository: _ProfileRepository(), onGoHome: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -720));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redefinir PIN'));
    await tester.pumpAndSettle();

    expect(find.byType(ChangePinScreen), findsOneWidget);
    expect(find.text('Crie seu novo PIN'), findsOneWidget);
  });

  testWidgets('pilot profile does not offer an unavailable PIN action', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen(onGoHome: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -720));
    await tester.pumpAndSettle();

    expect(find.text('Redefinir PIN'), findsNothing);
    expect(find.text('Sair do modo piloto'), findsOneWidget);

    await tester.tap(find.text('Sair do modo piloto'));
    await tester.pumpAndSettle();

    final dialogTitle = tester.widget<Text>(find.text('Sair do piloto?'));
    expect(dialogTitle.style?.fontFamily, 'Sora');
  });
}
