import 'dart:async';

import 'package:bingo_app/src/auth/auth_gateway.dart';
import 'package:bingo_app/src/screens/access_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modo piloto é uma escolha explícita sem login', (tester) async {
    var pilotCalls = 0;
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AccessFlowScreen(
          onEnterPilot: () => pilotCalls++,
          onSignIn: (_, _) async {
            signInCalls++;
            return null;
          },
        ),
      ),
    );

    await tester.ensureVisible(find.text('Entrar no modo piloto'));
    await tester.tap(find.text('Entrar no modo piloto'));
    expect(pilotCalls, 1);
    expect(signInCalls, 0);
  });

  testWidgets('login mostra loading e credencial inválida', (tester) async {
    final result = Completer<AuthFailure?>();
    await tester.pumpWidget(
      MaterialApp(
        home: AccessFlowScreen(
          onEnterPilot: () {},
          onSignIn: (_, _) => result.future,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Entrar com conta demo'));
    await tester.tap(find.text('Entrar com conta demo'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'demo@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'not-a-real-password',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Entrando...'), findsOneWidget);
    result.complete(
      const AuthFailure(
        AuthFailureKind.invalidCredentials,
        'E-mail ou senha inválidos.',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
  });

  testWidgets('configuração ausente é um erro explícito do login real', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccessFlowScreen(
          onEnterPilot: () {},
          onSignIn: (_, _) async => const AuthFailure(
            AuthFailureKind.missingConfiguration,
            'Configuração Supabase ausente: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY.',
          ),
        ),
      ),
    );

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
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('auth-error')), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.text('Entrar no modo piloto'), findsNothing);
  });
}
