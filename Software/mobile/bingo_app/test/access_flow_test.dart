import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileRepository implements ProfileRepository {
  StudentProfile? profile;
  String? pin;

  @override
  Future<void> deleteProfile() async {
    profile = null;
    pin = null;
  }

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
  }) async {
    return profile?.school == school &&
        profile?.identifier == identifier &&
        this.pin == pin;
  }

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

  testWidgets('access hub offers creation, login, and pilot mode', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(home: AccessFlowScreen(repository: _FakeProfileRepository())),
    );

    expect(find.text('Criar meu PIN'), findsOneWidget);
    expect(find.text('Já tenho PIN'), findsOneWidget);
    expect(find.text('Entrar no modo piloto'), findsOneWidget);
  });

  testWidgets('back from sign in returns to the access hub', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(home: AccessFlowScreen(repository: _FakeProfileRepository())),
    );

    await tester.tap(find.text('Já tenho PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Bom te ver de novo'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.text('Criar meu PIN'), findsOneWidget);
  });

  testWidgets('student creates and confirms a four digit PIN', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    final repository = _FakeProfileRepository();

    await tester.pumpWidget(
      MaterialApp(home: AccessFlowScreen(repository: repository)),
    );

    await tester.tap(find.text('Criar meu PIN'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'ENIAC');
    await tester.enterText(fields.at(1), '2026001');
    await tester.pump();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    for (final digit in ['4', '8', '2', '6']) {
      final key = find.text(digit);
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    for (final digit in ['4', '8', '2', '6']) {
      final key = find.text(digit);
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Confirmar PIN'));
    await tester.tap(find.text('Confirmar PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Tudo pronto!'), findsOneWidget);
    expect(repository.profile, const StudentProfile(school: 'ENIAC', identifier: '2026001'));
    expect(repository.pin, '4826');
  });
}
