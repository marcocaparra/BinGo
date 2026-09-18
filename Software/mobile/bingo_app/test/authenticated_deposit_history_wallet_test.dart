import 'dart:async';

import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = AuthenticatedStudentProfile(
  id: 'student-id',
  name: 'Ana Silva',
  schoolId: 'school-id',
  schoolName: 'ENIAC',
  classId: 'class-id',
  className: '3º A',
  pointsStudentBalance: 900,
  pointsClassBalance: 1800,
  status: 'active',
);

class _StaticProfileRepository implements AuthenticatedProfileRepository {
  const _StaticProfileRepository();

  @override
  Future<AuthenticatedStudentProfile> loadProfile() async => _profile;
}

class _FakeDepositHistoryRepository
    implements AuthenticatedDepositHistoryRepository {
  _FakeDepositHistoryRepository(this._load);

  final Future<List<AuthenticatedDepositHistoryEntry>> Function(
    int call,
    String studentId,
  )
  _load;
  int calls = 0;
  final requestedStudentIds = <String>[];

  @override
  Future<List<AuthenticatedDepositHistoryEntry>> loadHistory({
    required String studentId,
  }) {
    calls++;
    requestedStudentIds.add(studentId);
    return _load(calls, studentId);
  }
}

AuthenticatedDepositHistoryEntry _historyEntry({
  String id = 'deposit-id',
  String title = 'Pilha ou bateria',
  int binCoins = 137,
  int classXp = 91,
}) {
  return AuthenticatedDepositHistoryEntry(
    id: id,
    createdAt: DateTime(2026, 9, 5, 14, 30),
    isValid: true,
    detectedType: 'battery',
    category: DepositHistoryCategory(
      id: 'category-id',
      code: 'battery',
      displayName: title,
    ),
    categorySource: 'totem',
    bonusBinCoinsAwarded: 12,
    pointsAwardedStudent: binCoins,
    pointsAwardedClass: classXp,
  );
}

void _configureSurface(WidgetTester tester) {
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpAuthenticatedWallet(
  WidgetTester tester,
  AuthenticatedDepositHistoryRepository historyRepository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ShellScreen.authenticated(
        initialIndex: 1,
        repository: const _StaticProfileRepository(),
        depositHistoryRepository: historyRepository,
        missionsRepository: const _EmptyMissionsRepository(),
        onLogout: () async => null,
        onSessionInvalid: () async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _EmptyMissionsRepository implements AuthenticatedMissionsRepository {
  const _EmptyMissionsRepository();

  @override
  Future<List<AuthenticatedMission>> loadActiveMissions() async => const [];
}

Future<void> _openDiscards(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('wallet-tab-descartes')));
  await tester.pump();
}

void main() {
  testWidgets('authenticated wallet exposes loading then real history', (
    tester,
  ) async {
    _configureSurface(tester);
    final pending = Completer<List<AuthenticatedDepositHistoryEntry>>();
    final repository = _FakeDepositHistoryRepository((_, _) => pending.future);

    await _pumpAuthenticatedWallet(tester, repository);
    expect(find.text('Extrato indisponível'), findsOneWidget);

    await _openDiscards(tester);
    expect(find.text('Carregando histórico'), findsOneWidget);

    pending.complete([_historyEntry()]);
    await tester.pumpAndSettle();

    expect(find.text('Pilha ou bateria'), findsOneWidget);
    expect(find.text('+91 pts turma'), findsOneWidget);
    expect(find.text('Validado no Totem'), findsOneWidget);
    expect(repository.requestedStudentIds, ['student-id']);
  });

  testWidgets('authenticated wallet never displays pilot discard mocks', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeDepositHistoryRepository(
      (_, _) async => [_historyEntry()],
    );

    await _pumpAuthenticatedWallet(tester, repository);
    await tester.pumpAndSettle();
    await _openDiscards(tester);

    expect(find.text('Pilha ou bateria'), findsOneWidget);
    expect(find.text('Mouse sem uso'), findsNothing);
    expect(find.text('Cabo USB'), findsNothing);
    expect(find.text('Fone de ouvido'), findsNothing);
  });

  testWidgets('authenticated wallet exposes the existing empty state', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeDepositHistoryRepository((_, _) async => const []);

    await _pumpAuthenticatedWallet(tester, repository);
    await tester.pumpAndSettle();
    await _openDiscards(tester);

    expect(find.text('Nenhum descarte validado'), findsOneWidget);
    expect(
      find.text('Os descartes confirmados pelo Totem aparecerão aqui.'),
      findsOneWidget,
    );
  });

  testWidgets('authenticated wallet retries after a history error', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeDepositHistoryRepository((call, _) async {
      if (call == 1) {
        throw const DepositHistoryFailure(
          DepositHistoryFailureKind.network,
          'Sem conexão com o histórico.',
        );
      }
      return [_historyEntry(title: 'Eletrônico')];
    });

    await _pumpAuthenticatedWallet(tester, repository);
    await tester.pumpAndSettle();
    await _openDiscards(tester);

    expect(find.text('Descartes indisponíveis'), findsOneWidget);
    expect(find.text('Sem conexão com o histórico.'), findsOneWidget);

    await tester.ensureVisible(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Eletrônico'), findsOneWidget);
    expect(repository.calls, 2);
  });
}
