import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/change_pin_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileRepository implements ProfileRepository {
  StudentProfile? profile =
      const StudentProfile(school: 'ENIAC', identifier: 'Marco Caparra');
  String pin = '4826';

  @override
  Future<void> deleteProfile() async => profile = null;

  @override
  Future<bool> hasProfile() async => profile != null;

  @override
  Future<StudentProfile?> loadProfile() async => profile;

  @override
  Future<void> save({required StudentProfile profile, required String pin}) async {
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
        home: ProfileScreen(
          repository: _ProfileRepository(),
          onGoHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pontos pessoais'), findsOneWidget);
    expect(find.text('Pontos da turma'), findsOneWidget);
    expect(find.text('BinCoins'), findsOneWidget);
    for (final level in ['Aprendiz', 'Explorador', 'Restaurador', 'Guardião', 'Herói']) {
      expect(find.text(level), findsOneWidget);
    }
  });

  testWidgets('profile opens PIN redefinition', (WidgetTester tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          repository: _ProfileRepository(),
          onGoHome: () {},
        ),
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
      MaterialApp(home: ProfileScreen(onGoHome: () {})),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -720));
    await tester.pumpAndSettle();

    expect(find.text('Redefinir PIN'), findsNothing);
    expect(find.text('Sair do modo piloto'), findsOneWidget);
  });
}
