import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/change_pin_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/screens/splash_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/b1n_dialogue_strip.dart';
import 'package:bingo_app/src/widgets/bincoin_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileRepository
    implements ProfileRepository, ProfileCustomizationStore {
  StudentProfile? profile = const StudentProfile(
    school: 'ENIAC',
    identifier: 'Marco Caparra',
  );
  String pin = '4826';
  ProfileCustomization customization = const ProfileCustomization();

  @override
  Future<void> deleteProfile() async {
    profile = null;
    customization = const ProfileCustomization();
  }

  @override
  Future<bool> hasProfile() async => profile != null;

  @override
  Future<StudentProfile?> loadProfile() async => profile;

  @override
  Future<ProfileCustomization> loadCustomization() async => customization;

  @override
  Future<void> save({
    required StudentProfile profile,
    required String pin,
  }) async {
    this.profile = profile;
    this.pin = pin;
  }

  @override
  Future<void> saveCustomization(ProfileCustomization customization) async {
    this.customization = customization;
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

const _authenticatedProfile = AuthenticatedStudentProfile(
  id: 'student-id',
  name: 'Aluno do Backend',
  schoolId: 'school-id',
  schoolName: 'Escola Backend',
  classId: 'class-id',
  className: 'Turma Backend',
  pointsStudentBalance: 321,
  pointsClassBalance: 654,
  status: 'ACTIVE',
);

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
    final dialogue = tester.widget<B1nDialogueStrip>(
      find.byType(B1nDialogueStrip),
    );
    expect(dialogue.portrait, B1nPortraitVariant.celebration);
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

  testWidgets('profile saves unlocked avatar and theme choices', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen(repository: repository, onGoHome: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Personalizar perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Personalize sua jornada'), findsOneWidget);

    final b3nOption = find.text('Tio B3N');
    await tester.ensureVisible(b3nOption);
    await tester.tap(b3nOption);
    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();
    final scr4pTheme = find.text('Energia SCR4P');
    await tester.ensureVisible(scr4pTheme);
    await tester.tap(scr4pTheme);
    await tester.tap(find.text('Salvar personalização'));
    await tester.pumpAndSettle();

    expect(
      repository.customization,
      const ProfileCustomization(
        avatarId: 'b3n-shopkeeper',
        themeId: 'scr4p-purple',
      ),
    );
    expect(find.byTooltip('Personalizar perfil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'local profile customization migrates defaults and persists choices',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = LocalProfileRepository(preferences);

      expect(
        await repository.loadCustomization(),
        const ProfileCustomization(),
      );

      const selected = ProfileCustomization(
        avatarId: 'scr4p-defense',
        themeId: 'restoration-cyan',
      );
      await repository.saveCustomization(selected);
      expect(await repository.loadCustomization(), selected);

      await repository.deleteProfile();
      expect(
        await repository.loadCustomization(),
        const ProfileCustomization(),
      );
    },
  );

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

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('perfil autenticado usa o frontend final sem vazar mocks', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: _authenticatedProfile,
          onLogout: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aluno do Backend'), findsOneWidget);
    expect(
      find.textContaining('Escola Backend · Turma Backend'),
      findsOneWidget,
    );
    expect(find.text('321'), findsOneWidget);
    expect(find.text('654'), findsOneWidget);
    expect(find.text('BinCoins'), findsOneWidget);
    expect(find.text('XP da turma'), findsOneWidget);
    expect(find.text('Trilha do restaurador'), findsOneWidget);
    expect(find.text('Nível atual —'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Níveis, conquistas e progresso aparecerão quando tiverem uma fonte autenticada.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Marco'), findsNothing);
    expect(find.text('ENIAC'), findsNothing);
    expect(find.text('9ºA'), findsNothing);
    expect(find.text('120'), findsNothing);
    expect(find.text('760'), findsNothing);
    expect(find.text('1.190'), findsNothing);
    expect(find.text('Pontos pessoais'), findsNothing);
    expect(find.text('Nível 3 · Restaurador'), findsNothing);
    expect(find.text('Ver missões'), findsNothing);
  });

  testWidgets('logout autenticado mantém erro no Shell sem ativar piloto', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    var logoutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: _authenticatedProfile,
          onLogout: () async {
            logoutCalls++;
            return const AuthFailure(AuthFailureKind.network, 'Falha ao sair.');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -720));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair').last);
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
    expect(find.text('Falha ao sair.'), findsOneWidget);
    expect(find.textContaining('Marco'), findsNothing);
  });
}
