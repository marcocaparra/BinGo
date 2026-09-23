import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:bingo_app/src/screens/change_pin_screen.dart';
import 'package:bingo_app/src/screens/profile_screen.dart';
import 'package:bingo_app/src/screens/splash_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/bingo_widgets.dart';
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

class _CustomizationStore implements ProfileCustomizationStore {
  _CustomizationStore([this.customization = const ProfileCustomization()]);

  ProfileCustomization customization;
  int saveCalls = 0;

  @override
  Future<ProfileCustomization> loadCustomization() async => customization;

  @override
  Future<void> saveCustomization(ProfileCustomization customization) async {
    saveCalls++;
    this.customization = customization;
  }
}

const _level3Progress = AuthenticatedProfileProgress(
  studentId: 'student-id',
  validDepositCount: 12,
  levelNumber: 3,
  levelCode: 'RESTORER',
  remainingToNextLevel: 8,
  progressToNextLevel: 0.6,
);

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
  progress: _level3Progress,
);

AuthenticatedStudentProfile authenticatedProfileWithProgress(
  AuthenticatedProfileProgress progress,
) {
  return AuthenticatedStudentProfile(
    id: progress.studentId,
    name: 'Aluno do Backend',
    schoolId: 'school-id',
    schoolName: 'Escola Backend',
    classId: 'class-id',
    className: 'Turma Backend',
    pointsStudentBalance: 321,
    pointsClassBalance: 654,
    status: 'ACTIVE',
    progress: progress,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
          tester.getTopLeft(find.text('76.000')).dy,
          tester.getTopLeft(find.text('119.000')).dy,
          tester.getTopLeft(find.text('12.000')).dy,
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
        expect(find.bySemanticsLabel('12000 BinCoins'), findsOneWidget);
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
    expect(find.text('Nível 3 · Restaurador'), findsOneWidget);
    expect(find.text('N3'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedProgressPill>(find.byType(AnimatedProgressPill))
          .value,
      0.6,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Descartes'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Você já fez 12 descartes válidos. Faltam 8 para chegar a Guardião.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Marco'), findsNothing);
    expect(find.text('ENIAC'), findsNothing);
    expect(find.text('9ºA'), findsNothing);
    expect(find.text('12.000'), findsNothing);
    expect(find.text('76.000'), findsNothing);
    expect(find.text('119.000'), findsNothing);
    expect(find.text('Pontos pessoais'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.byTooltip('Personalizar perfil'), findsOneWidget);
    expect(find.text('Dados autenticados'), findsNothing);
    expect(find.text('Ver missões'), findsNothing);
  });

  testWidgets('nível 0 autenticado renderiza início da Trilha', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    const progress = AuthenticatedProfileProgress(
      studentId: 'student-zero',
      validDepositCount: 0,
      levelNumber: 0,
      levelCode: 'NONE',
      remainingToNextLevel: 1,
      progressToNextLevel: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: authenticatedProfileWithProgress(progress),
          customizationStore: _CustomizationStore(),
          onLogout: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('N0'), findsOneWidget);
    expect(find.text('Nível 0'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedProgressPill>(find.byType(AnimatedProgressPill))
          .value,
      0,
    );
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Descartes'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(
      find.text('Faça seu primeiro descarte válido para chegar a Aprendiz.'),
      findsOneWidget,
    );
  });

  testWidgets('nível 1 autenticado renderiza progresso real', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    const progress = AuthenticatedProfileProgress(
      studentId: 'student-one',
      validDepositCount: 1,
      levelNumber: 1,
      levelCode: 'APPRENTICE',
      remainingToNextLevel: 4,
      progressToNextLevel: 0.2,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: authenticatedProfileWithProgress(progress),
          customizationStore: _CustomizationStore(),
          onLogout: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('N1'), findsOneWidget);
    expect(find.text('Nível 1 · Aprendiz'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedProgressPill>(find.byType(AnimatedProgressPill))
          .value,
      0.2,
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(
      find.text(
        'Você já fez 1 descartes válidos. Faltam 4 para chegar a Explorador.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('nível 5 autenticado mantém Herói e todas as etapas anteriores', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    const progress = AuthenticatedProfileProgress(
      studentId: 'student-hero',
      validDepositCount: 73,
      levelNumber: 5,
      levelCode: 'HERO',
      remainingToNextLevel: 0,
      progressToNextLevel: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: authenticatedProfileWithProgress(progress),
          customizationStore: _CustomizationStore(),
          onLogout: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('N5'), findsOneWidget);
    expect(find.text('Nível 5 · Herói'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedProgressPill>(find.byType(AnimatedProgressPill))
          .value,
      1,
    );
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
    expect(
      find.text('Você já fez 73 descartes válidos e alcançou o nível Herói.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'personalização autenticada salva localmente e reaparece ao recriar a tela',
    (WidgetTester tester) async {
      reduceMotion(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _CustomizationStore();

      Widget buildScreen() => MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: _authenticatedProfile,
          customizationStore: store,
          onLogout: () async => null,
        ),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Personalizar perfil'));
      await tester.pumpAndSettle();

      expect(find.text('B1N guia · Cidade azul'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      await tester.tap(find.text('Tio B3N'));
      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      await tester.tap(find.text('Energia SCR4P'));
      await tester.tap(find.text('Salvar personalização'));
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(
        store.customization,
        const ProfileCustomization(
          avatarId: 'b3n-shopkeeper',
          themeId: 'scr4p-purple',
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Personalizar perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Tio B3N · Energia SCR4P'), findsOneWidget);
    },
  );

  testWidgets('bloqueios da personalização usam o nível real da Trilha', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> expectAvatarLocks(
      AuthenticatedProfileProgress progress,
      int expectedLocks,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ProfileScreen.authenticated(
            profile: authenticatedProfileWithProgress(progress),
            customizationStore: _CustomizationStore(),
            onLogout: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Personalizar perfil'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(expectedLocks));
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
    }

    await expectAvatarLocks(
      const AuthenticatedProfileProgress(
        studentId: 'student-zero',
        validDepositCount: 0,
        levelNumber: 0,
        levelCode: 'NONE',
        remainingToNextLevel: 1,
        progressToNextLevel: 0,
      ),
      6,
    );
    await expectAvatarLocks(_level3Progress, 2);
    await expectAvatarLocks(
      const AuthenticatedProfileProgress(
        studentId: 'student-five',
        validDepositCount: 50,
        levelNumber: 5,
        levelCode: 'HERO',
        remainingToNextLevel: 0,
        progressToNextLevel: 1,
      ),
      0,
    );
  });

  testWidgets('preferência acima do nível atual é preservada sem desbloqueio', (
    WidgetTester tester,
  ) async {
    reduceMotion(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _CustomizationStore(
      const ProfileCustomization(avatarId: 'b1n-hero', themeId: 'hero-navy'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileScreen.authenticated(
          profile: _authenticatedProfile,
          customizationStore: store,
          onLogout: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Personalizar perfil'));
    await tester.pumpAndSettle();

    expect(find.text('B1N restaurador · Herói da cidade'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
    await tester.tap(find.text('Salvar personalização'));
    await tester.pumpAndSettle();

    expect(store.saveCalls, 0);
    expect(
      store.customization,
      const ProfileCustomization(avatarId: 'b1n-hero', themeId: 'hero-navy'),
    );
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
