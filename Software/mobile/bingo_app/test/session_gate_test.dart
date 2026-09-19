import 'dart:async';

import 'package:bingo_app/src/app.dart';
import 'package:bingo_app/src/auth/access_restore_store.dart';
import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/config/supabase_config.dart';
import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
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

const _remoteProfile = AuthenticatedStudentProfile(
  id: 'student-id',
  name: 'REMOTE PROFILE ONLY',
  schoolId: 'school-id',
  schoolName: 'Remote School',
  classId: 'class-id',
  className: 'Remote Class',
  pointsStudentBalance: 17,
  pointsClassBalance: 29,
  status: 'ACTIVE',
);

class _FakeRestoreStore implements AccessRestoreStore {
  _FakeRestoreStore(this.restore);

  bool restore;
  int marks = 0;
  int clears = 0;

  @override
  Future<void> clearAuthenticatedSession() async {
    clears++;
    restore = false;
  }

  @override
  Future<void> markAuthenticatedSession() async {
    marks++;
    restore = true;
  }

  @override
  Future<bool> shouldRestoreAuthenticatedSession() async => restore;
}

class _FakeRemoteRepository implements AuthenticatedProfileRepository {
  _FakeRemoteRepository({this.failure});

  final ProfileFailure? failure;
  int calls = 0;

  @override
  Future<AuthenticatedStudentProfile> loadProfile() async {
    calls++;
    if (failure != null) throw failure!;
    return _remoteProfile;
  }
}

class _FakeGateway implements AuthGateway {
  _FakeGateway({
    required this.profileRepository,
    this.restoreSessionResult = false,
    this.signInFailure,
  }) : depositHistoryRepository = const _EmptyDepositHistoryRepository();

  @override
  final AuthenticatedMissionsRepository missionsRepository =
      const _EmptyMissionsRepository();

  @override
  final AuthenticatedProfileRepository profileRepository;

  @override
  final AuthenticatedDepositHistoryRepository depositHistoryRepository;
  final bool restoreSessionResult;
  final AuthFailure? signInFailure;
  final StreamController<AuthSessionEvent> events =
      StreamController<AuthSessionEvent>.broadcast();
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Stream<AuthSessionEvent> get sessionEvents => events.stream;

  @override
  Future<bool> restoreSession() async => restoreSessionResult;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    if (signInFailure != null) throw signInFailure!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> close() async {
    await events.close();
  }
}

class _EmptyDepositHistoryRepository
    implements AuthenticatedDepositHistoryRepository {
  const _EmptyDepositHistoryRepository();

  @override
  Future<List<AuthenticatedDepositHistoryEntry>> loadHistory({
    required String studentId,
  }) async => const [];
}

class _EmptyMissionsRepository implements AuthenticatedMissionsRepository {
  const _EmptyMissionsRepository();

  @override
  Future<List<AuthenticatedMission>> loadActiveMissions() async => const [];
}

class _FakeFactory implements AuthGatewayFactory {
  _FakeFactory(this.gateway);

  final AuthGateway gateway;
  int createCalls = 0;

  @override
  Future<AuthGateway> create() async {
    createCalls++;
    return gateway;
  }
}

class _MissingConfigFactory implements AuthGatewayFactory {
  int createCalls = 0;

  @override
  Future<AuthGateway> create() async {
    createCalls++;
    throw const SupabaseConfigurationException([
      'SUPABASE_URL',
      'SUPABASE_PUBLISHABLE_KEY',
    ]);
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

  Future<void> enterEmailCredentials(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Entrar com e-mail'));
    await tester.tap(find.text('Entrar com e-mail'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'demo@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'password',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  SessionGate localGate(ProfileRepository repository) {
    return SessionGate(
      repository: repository,
      authGatewayFactory: _FakeFactory(
        _FakeGateway(profileRepository: _FakeRemoteRepository()),
      ),
      restoreStore: _FakeRestoreStore(false),
    );
  }

  testWidgets('saved local profile opens the isolated pilot after the splash', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(home: localGate(_SessionRepository(hasSavedProfile: true))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Olá, Marco!'), findsOneWidget);
  });

  testWidgets('empty device opens access flow without onboarding', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(home: localGate(_SessionRepository(hasSavedProfile: false))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('access-hub')), findsOneWidget);
    expect(find.text('Pronto para continuar sua jornada?'), findsOneWidget);
    expect(find.text('Entrar com e-mail'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
  });

  testWidgets('splash remains visible for the 2.8 second reveal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: localGate(_SessionRepository(hasSavedProfile: false))),
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
    await tester.pumpWidget(MaterialApp(home: localGate(repository)));
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
    await tester.pumpWidget(MaterialApp(home: localGate(repository)));
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

  testWidgets('configuração Supabase válida cria gateway e abre o Shell', (
    tester,
  ) async {
    reduceMotion(tester);
    final store = _FakeRestoreStore(false);
    final gateway = _FakeGateway(
      profileRepository: _FakeRemoteRepository(),
      restoreSessionResult: true,
    );
    final factory = _FakeFactory(gateway);
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: factory,
        restoreStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.text('Olá, REMOTE!'), findsOneWidget);
    expect(find.text('Remote School · Remote Class'), findsOneWidget);
    expect(find.textContaining('Marco'), findsNothing);
    expect(store.marks, 1);
    expect(store.restore, isTrue);
    expect(factory.createCalls, 1);
  });

  testWidgets('ausência de sessão SDK limpa marcador e abre acesso final', (
    tester,
  ) async {
    reduceMotion(tester);
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(profileRepository: _FakeRemoteRepository());
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.text('Entrar com e-mail'), findsOneWidget);
    expect(store.clears, 1);
  });

  testWidgets('login por e-mail entra no Shell e mostra saldos reais', (
    tester,
  ) async {
    reduceMotion(tester);
    final store = _FakeRestoreStore(false);
    final gateway = _FakeGateway(profileRepository: _FakeRemoteRepository());
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: store,
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('access-hub')), findsOneWidget);
    expect(find.text('Pronto para continuar sua jornada?'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    await enterEmailCredentials(tester);

    expect(gateway.signInCalls, 1);
    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.text('Ainda não há dados'), findsOneWidget);
    expect(find.text('Jornada da turma'), findsOneWidget);
    expect(find.text('Missão ainda não vinculada'), findsOneWidget);
    expect(find.text('Ver preparo para o Totem'), findsOneWidget);
    expect(find.text('Alerta SCR4P'), findsOneWidget);
    expect(find.text('68% restaurada'), findsNothing);
    expect(find.textContaining('2 descartes'), findsNothing);
    expect(find.text('Como funciona o BinGo'), findsOneWidget);
    expect(find.text('Dados autenticados'), findsNothing);
    expect(find.textContaining('Marco'), findsNothing);

    await tester.ensureVisible(find.text('Como funciona o BinGo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Como funciona o BinGo'));
    await tester.pumpAndSettle();
    expect(find.text('Como funciona'), findsOneWidget);
    expect(find.text('Dados simulados'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carteira'));
    await tester.pumpAndSettle();
    expect(find.text('17'), findsOneWidget);
    expect(find.text('12.000'), findsNothing);
    expect(find.text('Abrir BinBazar'), findsOneWidget);
    expect(find.text('Extrato indisponível'), findsOneWidget);

    await tester.tap(find.text('Missões'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma missão individual ativa'), findsOneWidget);
    expect(find.text('Força-tarefa em destaque'), findsOneWidget);
    expect(find.text('Nenhuma missão coletiva ativa'), findsOneWidget);
    expect(find.text('Outras etapas da jornada'), findsOneWidget);
    expect(find.text('Ainda não há outras etapas'), findsOneWidget);

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.text('Sua turma · Remote Class'), findsOneWidget);
    expect(find.text('29 XP'), findsOneWidget);
    expect(find.text('Turmas da Praça'), findsOneWidget);
    expect(find.text('Turma —'), findsNWidgets(3));
    expect(find.text('Ainda não há dados'), findsOneWidget);
    expect(find.text('7ºA'), findsNothing);
    expect(find.text('8ºB'), findsNothing);
    expect(find.text('6ºC'), findsNothing);
    expect(find.text('12 dias'), findsNothing);

    await tester.ensureVisible(find.text('Explorar BinGópolis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar BinGópolis'));
    await tester.pumpAndSettle();
    expect(find.text('BinGópolis'), findsOneWidget);
    expect(find.text('Ainda não há dados'), findsOneWidget);
    expect(find.text('Dados simulados'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('29'), findsOneWidget);
    expect(find.text('XP da turma'), findsOneWidget);
    expect(find.text('Pontos pessoais'), findsOneWidget);
    expect(find.text('9ºA'), findsNothing);
  });

  testWidgets('sair do piloto retorna ao hub Supabase sem expor PIN local', (
    tester,
  ) async {
    reduceMotion(tester);
    final gateway = _FakeGateway(profileRepository: _FakeRemoteRepository());
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Marco!'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair do modo piloto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('access-hub')), findsOneWidget);
    expect(find.text('Entrar com e-mail'), findsOneWidget);
    expect(find.text('Criar meu PIN'), findsNothing);
    expect(find.text('Já tenho PIN'), findsNothing);
    expect(gateway.signOutCalls, 0);
  });

  testWidgets('configuração ausente é explícita sem bloquear o piloto', (
    tester,
  ) async {
    reduceMotion(tester);
    final factory = _MissingConfigFactory();
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: factory,
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await tester.pumpAndSettle();
    await enterEmailCredentials(tester);

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar no modo piloto'));
    await tester.pumpAndSettle();
    expect(find.byType(ShellScreen), findsOneWidget);
    expect(factory.createCalls, 2);
  });

  testWidgets(
    'configuração ausente com marcador antigo não vaza exceção assíncrona',
    (tester) async {
      final store = _FakeRestoreStore(true);
      final factory = _MissingConfigFactory();
      await tester.pumpWidget(
        BingoApp(
          repository: _SessionRepository(hasSavedProfile: false),
          authGatewayFactory: factory,
          restoreStore: store,
        ),
      );
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 260));

      expect(tester.takeException(), isNull);
      expect(find.byType(AccessFlowScreen), findsOneWidget);
      expect(store.restore, isFalse);
      expect(factory.createCalls, 1);

      await tester.ensureVisible(find.text('Entrar no modo piloto'));
      await tester.tap(find.text('Entrar no modo piloto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.byType(ShellScreen), findsOneWidget);
    },
  );

  testWidgets('credenciais inválidas permanecem no acesso autenticado', (
    tester,
  ) async {
    reduceMotion(tester);
    final gateway = _FakeGateway(
      profileRepository: _FakeRemoteRepository(),
      signInFailure: const AuthFailure(
        AuthFailureKind.invalidCredentials,
        'E-mail ou senha inválidos.',
      ),
    );
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await tester.pumpAndSettle();
    await enterEmailCredentials(tester);

    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('falha remota não ativa dados piloto', (tester) async {
    reduceMotion(tester);
    final gateway = _FakeGateway(
      profileRepository: _FakeRemoteRepository(
        failure: const ProfileFailure(
          ProfileFailureKind.network,
          'Falha de rede controlada.',
        ),
      ),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.text('Falha de rede controlada.'), findsOneWidget);
    expect(find.textContaining('Marco'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('sessão expirada retorna ao acesso final', (tester) async {
    reduceMotion(tester);
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(
      profileRepository: _FakeRemoteRepository(
        failure: const ProfileFailure(
          ProfileFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
        ),
      ),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(store.clears, greaterThan(0));
    expect(find.textContaining('Marco'), findsNothing);
  });

  testWidgets('logout encerra sessão e volta ao acesso final', (tester) async {
    reduceMotion(tester);
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(
      profileRepository: _FakeRemoteRepository(),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(
        repository: _SessionRepository(hasSavedProfile: false),
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -720));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair').last);
    await tester.pumpAndSettle();

    expect(gateway.signOutCalls, 1);
    expect(find.byType(AccessFlowScreen), findsOneWidget);
    expect(find.textContaining('Marco'), findsNothing);
    expect(store.restore, isFalse);
  });
}
