import 'dart:async';

import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/authenticated_profile_screen.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = StudentProfile(
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

class _Repository implements ProfileRepository {
  _Repository(this.loader);

  final Future<StudentProfile> Function() loader;
  int calls = 0;

  @override
  Future<StudentProfile> loadProfile() {
    calls++;
    return loader();
  }
}

Widget _app(
  ProfileRepository repository, {
  Future<void> Function()? onSessionInvalid,
  Future<AuthFailure?> Function()? onLogout,
}) {
  return MaterialApp(
    home: AuthenticatedProfileScreen(
      repository: repository,
      onSessionInvalid: onSessionInvalid ?? () async {},
      onLogout: onLogout ?? () async => null,
    ),
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('perfil autenticado mostra loading sem perfil fictício', (
    tester,
  ) async {
    final completer = Completer<StudentProfile>();
    await tester.pumpWidget(_app(_Repository(() => completer.future)));

    expect(find.text('Carregando perfil'), findsOneWidget);
    expect(find.text('Marco Caparra'), findsNothing);
    expect(find.text('Aluno do Backend'), findsNothing);

    completer.complete(_profile);
    await _pumpUi(tester);
  });

  testWidgets('sucesso mostra somente campos remotos disponíveis', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository(() async => _profile)));
    await _pumpUi(tester);

    expect(find.text('Aluno do Backend'), findsOneWidget);
    expect(find.text('Escola Backend'), findsOneWidget);
    expect(find.text('Turma Backend'), findsOneWidget);
    expect(find.text('321'), findsOneWidget);
    expect(find.text('654'), findsOneWidget);
    expect(find.text('Dados remotos'), findsOneWidget);
    expect(find.text('Marco Caparra'), findsNothing);
    expect(find.text('120'), findsNothing);
    expect(find.textContaining('não estão disponíveis'), findsOneWidget);
  });

  testWidgets('vínculo Auth–aluno ausente mostra erro e retry', (tester) async {
    var shouldFail = true;
    final repository = _Repository(() async {
      if (shouldFail) {
        throw const ProfileFailure(
          ProfileFailureKind.authLinkMissing,
          'Esta conta ainda não está vinculada a um aluno BinGo.',
        );
      }
      return _profile;
    });
    await tester.pumpWidget(_app(repository));
    await _pumpUi(tester);

    expect(find.text('Conta sem vínculo de aluno'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Marco Caparra'), findsNothing);

    shouldFail = false;
    await tester.tap(find.text('Tentar novamente'));
    await _pumpUi(tester);
    expect(find.text('Aluno do Backend'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('sessão inválida apresenta estado e solicita retorno', (
    tester,
  ) async {
    var invalidCalls = 0;
    await tester.pumpWidget(
      _app(
        _Repository(
          () async => throw const ProfileFailure(
            ProfileFailureKind.sessionInvalid,
            'Sua sessão expirou. Entre novamente.',
          ),
        ),
        onSessionInvalid: () async => invalidCalls++,
      ),
    );
    await _pumpUi(tester);

    expect(find.text('Sessão expirada'), findsOneWidget);
    expect(invalidCalls, 1);
    expect(find.text('Marco Caparra'), findsNothing);
  });

  testWidgets('logout real delega ao gateway e mostra erro sem piloto', (
    tester,
  ) async {
    var logoutCalls = 0;
    await tester.pumpWidget(
      _app(
        _Repository(() async => _profile),
        onLogout: () async {
          logoutCalls++;
          return const AuthFailure(AuthFailureKind.network, 'Falha ao sair.');
        },
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byTooltip('Sair da conta'));
    await _pumpUi(tester);

    expect(logoutCalls, 1);
    expect(find.text('Falha ao sair.'), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });

  testWidgets('shell piloto preserva os mocks e identifica o modo', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
    await _pumpUi(tester);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == 'MODO PILOTO',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Marco'), findsWidgets);
    expect(find.text('REMOTE PROFILE ONLY'), findsNothing);
  });
}
