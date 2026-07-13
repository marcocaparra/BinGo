import 'package:bingo_app/src/app.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/onboarding_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionRepository implements ProfileRepository {
  _SessionRepository({required this.hasSavedProfile});

  bool hasSavedProfile;

  @override
  Future<void> deleteProfile() async => hasSavedProfile = false;

  @override
  Future<bool> hasProfile() async => hasSavedProfile;

  @override
  Future<StudentProfile?> loadProfile() async => hasSavedProfile
      ? const StudentProfile(school: 'ENIAC', identifier: 'Marco')
      : null;

  @override
  Future<void> save({required StudentProfile profile, required String pin}) async {
    hasSavedProfile = true;
  }

  @override
  Future<bool> verify({
    required String school,
    required String identifier,
    required String pin,
  }) async => hasSavedProfile;

  @override
  Future<bool> resetPin({
    required String school,
    required String identifier,
    required String newPin,
  }) async => hasSavedProfile;
}

void main() {
  void reduceMotion(WidgetTester tester) {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
  }

  testWidgets('saved profile opens the shell without onboarding', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          repository: _SessionRepository(hasSavedProfile: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('empty device opens onboarding', (WidgetTester tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          repository: _SessionRepository(hasSavedProfile: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
