import 'dart:async';

import 'package:bingo_app/src/app.dart';
import 'package:bingo_app/src/auth/access_restore_store.dart';
import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/config/supabase_config.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/authenticated_profile_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _remoteProfile = StudentProfile(
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

class _FakeRepository implements ProfileRepository {
  _FakeRepository({this.failure});

  final ProfileFailure? failure;
  int calls = 0;

  @override
  Future<StudentProfile> loadProfile() async {
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
  });

  @override
  final ProfileRepository profileRepository;
  final bool restoreSessionResult;
  final AuthFailure? signInFailure;
  final StreamController<AuthSessionEvent> events =
      StreamController<AuthSessionEvent>.broadcast();
  int restoreSessionCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Stream<AuthSessionEvent> get sessionEvents => events.stream;

  @override
  Future<bool> restoreSession() async {
    restoreSessionCalls++;
    return restoreSessionResult;
  }

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

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _openAccess(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Começar missão'));
  await tester.tap(find.text('Começar missão'));
  await _pumpUi(tester);
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Entrar com conta demo'));
  await tester.tap(find.text('Entrar com conta demo'));
  await tester.pump();
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
  await _pumpUi(tester);
}

void main() {
  testWidgets('piloto não carrega repository remoto quando não há sessão', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final gateway = _FakeGateway(profileRepository: repository);
    final factory = _FakeFactory(gateway);
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: factory,
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await _pumpUi(tester);

    await _openAccess(tester);
    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    await _pumpUi(tester);

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == 'MODO PILOTO',
      ),
      findsOneWidget,
    );
    expect(factory.createCalls, 1);
    expect(gateway.restoreSessionCalls, 1);
    expect(repository.calls, 0);
    expect(find.textContaining('Marco'), findsWidgets);
  });

  testWidgets('configuração ausente não afeta piloto', (tester) async {
    final factory = _MissingConfigFactory();
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: factory,
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await _pumpUi(tester);
    await _openAccess(tester);
    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    await _pumpUi(tester);

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(factory.createCalls, 1);
  });

  testWidgets('configuração ausente bloqueia login real explicitamente', (
    tester,
  ) async {
    final factory = _MissingConfigFactory();
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: factory,
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await _pumpUi(tester);
    await _openAccess(tester);
    await _enterCredentials(tester);

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
    expect(factory.createCalls, 2);
  });

  testWidgets('sessão restaurada seleciona perfil remoto sem mocks', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(true),
      ),
    );
    await _pumpUi(tester);

    expect(find.byType(AuthenticatedProfileScreen), findsOneWidget);
    expect(find.text('REMOTE PROFILE ONLY'), findsOneWidget);
    expect(find.text('Marco Caparra'), findsNothing);
    expect(find.textContaining('BinCoins'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('sessão Supabase válida restaura mesmo sem marcador auxiliar', (
    tester,
  ) async {
    final store = _FakeRestoreStore(false);
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(authGatewayFactory: _FakeFactory(gateway), restoreStore: store),
    );
    await _pumpUi(tester);

    expect(find.text('REMOTE PROFILE ONLY'), findsOneWidget);
    expect(store.marks, 1);
    expect(store.restore, isTrue);
  });

  testWidgets('marcador auxiliar é limpo quando SDK não possui sessão', (
    tester,
  ) async {
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(profileRepository: _FakeRepository());
    await tester.pumpWidget(
      BingoApp(authGatewayFactory: _FakeFactory(gateway), restoreStore: store),
    );
    await _pumpUi(tester);

    expect(find.text('Começar missão'), findsOneWidget);
    expect(store.clears, 1);
    expect(find.byType(AuthenticatedProfileScreen), findsNothing);
  });

  testWidgets('erro remoto não ativa piloto', (tester) async {
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(
        failure: const ProfileFailure(
          ProfileFailureKind.network,
          'Falha de rede controlada.',
        ),
      ),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(true),
      ),
    );
    await _pumpUi(tester);

    expect(find.text('Falha de rede controlada.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('sessão expirada retorna à entrada', (tester) async {
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(
        failure: const ProfileFailure(
          ProfileFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
        ),
      ),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(authGatewayFactory: _FakeFactory(gateway), restoreStore: store),
    );
    await _pumpUi(tester);

    expect(find.text('Começar missão'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
    expect(store.clears, greaterThan(0));
  });

  testWidgets('logout encerra sessão e não entra no piloto', (tester) async {
    final store = _FakeRestoreStore(true);
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(),
      restoreSessionResult: true,
    );
    await tester.pumpWidget(
      BingoApp(authGatewayFactory: _FakeFactory(gateway), restoreStore: store),
    );
    await _pumpUi(tester);

    await tester.tap(find.text('Sair da conta'));
    await _pumpUi(tester);

    expect(gateway.signOutCalls, 1);
    expect(find.text('Começar missão'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('login válido marca restauração e seleciona remoto', (
    tester,
  ) async {
    final store = _FakeRestoreStore(false);
    final gateway = _FakeGateway(profileRepository: _FakeRepository());
    await tester.pumpWidget(
      BingoApp(authGatewayFactory: _FakeFactory(gateway), restoreStore: store),
    );
    await _pumpUi(tester);
    await _openAccess(tester);
    await _enterCredentials(tester);

    expect(gateway.signInCalls, 1);
    expect(store.marks, 1);
    expect(find.text('REMOTE PROFILE ONLY'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('credenciais inválidas permanecem na entrada autenticada', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      profileRepository: _FakeRepository(),
      signInFailure: const AuthFailure(
        AuthFailureKind.invalidCredentials,
        'E-mail ou senha inválidos.',
      ),
    );
    await tester.pumpWidget(
      BingoApp(
        authGatewayFactory: _FakeFactory(gateway),
        restoreStore: _FakeRestoreStore(false),
      ),
    );
    await _pumpUi(tester);
    await _openAccess(tester);
    await _enterCredentials(tester);

    expect(gateway.signInCalls, 1);
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(find.byType(AuthenticatedProfileScreen), findsNothing);
    expect(find.byType(ShellScreen), findsNothing);
  });
}
