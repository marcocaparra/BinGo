import 'dart:async';

import 'package:bingo_app/src/app.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionRepository implements ProfileRepository {
  _SessionRepository({required this.hasSavedProfile, this.hasProfileOverride});

  bool hasSavedProfile;
  Future<bool> Function()? hasProfileOverride;

  @override
  Future<void> deleteProfile() async => hasSavedProfile = false;

  @override
  Future<bool> hasProfile() async =>
      hasProfileOverride?.call() ?? hasSavedProfile;

  @override
  Future<StudentProfile?> loadProfile() async => hasSavedProfile
      ? const StudentProfile(school: 'ENIAC', identifier: 'Gustavo Alencar')
      : null;

  @override
  Future<void> save({
    required StudentProfile profile,
    required String pin,
  }) async {
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

  testWidgets('saved profile opens the shell after the splash', (tester) async {
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
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Olá, Gustavo!'), findsOneWidget);
  });

  testWidgets('empty device opens access flow without onboarding', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          repository: _SessionRepository(hasSavedProfile: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.text('Criar meu PIN'), findsOneWidget);
  });

  testWidgets('splash remains visible for the 2.8 second reveal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          repository: _SessionRepository(hasSavedProfile: false),
        ),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2799));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byType(AccessFlowScreen), findsOneWidget);
  });

  testWidgets('splash waits for a slower session lookup', (tester) async {
    final completer = Completer<bool>();
    final repository = _SessionRepository(
      hasSavedProfile: false,
      hasProfileOverride: () => completer.future,
    );
    await tester.pumpWidget(
      MaterialApp(home: SessionGate(repository: repository)),
    );
    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.byType(SplashScreen), findsOneWidget);
    completer.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byType(AccessFlowScreen), findsOneWidget);
  });

  testWidgets('session error offers a retry instead of hanging', (
    tester,
  ) async {
    reduceMotion(tester);
    var attempts = 0;
    final repository = _SessionRepository(
      hasSavedProfile: false,
      hasProfileOverride: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('storage unavailable');
        return false;
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: SessionGate(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Tentar novamente'), findsOneWidget);
    await tester.tap(find.byTooltip('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(attempts, 2);
  });

  for (final size in [const Size(390, 844), const Size(430, 932)]) {
    testWidgets('splash fits ${size.width}x${size.height} at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      reduceMotion(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SplashScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
