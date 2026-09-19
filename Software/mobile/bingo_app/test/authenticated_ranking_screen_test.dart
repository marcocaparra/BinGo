import 'dart:async';

import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/ranking_repository.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/bingo_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = AuthenticatedStudentProfile(
  id: 'student-id',
  name: 'Ana Silva',
  schoolId: 'school-id',
  schoolName: 'Escola BinGo',
  classId: 'class-current',
  className: 'Turma Atual',
  pointsStudentBalance: 1600,
  pointsClassBalance: 1900,
  status: 'ACTIVE',
);

class _StaticProfileRepository implements AuthenticatedProfileRepository {
  const _StaticProfileRepository();

  @override
  Future<AuthenticatedStudentProfile> loadProfile() async => _profile;
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

class _FakeRankingRepository implements AuthenticatedRankingRepository {
  _FakeRankingRepository(this.load);

  final Future<ClassRanking> Function(String currentClassId) load;
  int calls = 0;

  @override
  Future<ClassRanking> loadRanking({required String currentClassId}) {
    calls++;
    return load(currentClassId);
  }
}

ClassRankingEntry entry(String id, String name, int xp) {
  return ClassRankingEntry(
    classId: id,
    className: name,
    pointsClassBalance: xp,
  );
}

ClassRanking ranking(
  List<ClassRankingEntry> entries, {
  required String currentClassId,
}) {
  final index = entries.indexWhere((item) => item.classId == currentClassId);
  return ClassRanking(
    entries: List.unmodifiable(entries),
    currentClassIndex: index < 0 ? null : index,
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

Future<void> _pumpAuthenticatedRanking(
  WidgetTester tester,
  AuthenticatedRankingRepository repository, {
  Future<void> Function()? onSessionInvalid,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ShellScreen.authenticated(
        initialIndex: 3,
        repository: const _StaticProfileRepository(),
        depositHistoryRepository: const _EmptyDepositHistoryRepository(),
        missionsRepository: const _EmptyMissionsRepository(),
        rankingRepository: repository,
        onLogout: () async => null,
        onSessionInvalid: onSessionInvalid ?? () async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('authenticated ranking exposes loading', (tester) async {
    _configureSurface(tester);
    final pending = Completer<ClassRanking>();

    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository((_) => pending.future),
    );

    expect(find.text('Carregando Ranking'), findsOneWidget);
    pending.complete(const ClassRanking(entries: [], currentClassIndex: null));
    await tester.pumpAndSettle();
  });

  testWidgets('empty ranking preserves canonical structure without demos', (
    tester,
  ) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (_) async => const ClassRanking(entries: [], currentClassIndex: null),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ranking das turmas'), findsOneWidget);
    expect(
      find.text('Compare posições e acompanhe a restauração coletiva.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ranking-hero')), findsOneWidget);
    expect(find.byKey(const Key('ranking-podium')), findsOneWidget);
    expect(find.text('Explorar BinGópolis'), findsOneWidget);
    expect(find.text('Sua turma · —'), findsOneWidget);
    expect(find.text('Turma —'), findsNWidgets(3));
    expect(find.text('7ºA'), findsNothing);
    expect(find.text('124.000 pts'), findsNothing);
    expect(find.text('12 dias'), findsNothing);
  });

  testWidgets('one class fills only first podium place and the real hero', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeRankingRepository(
      (currentClassId) async => ranking([
        entry('class-current', 'Turma Atual', 0),
      ], currentClassId: currentClassId),
    );

    await _pumpAuthenticatedRanking(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('1º lugar'), findsOneWidget);
    expect(find.text('1º'), findsOneWidget);
    expect(find.text('0 XP'), findsNWidgets(2));
    expect(find.text('Turma Atual'), findsOneWidget);
    expect(find.text('Turma —'), findsNWidgets(2));
    expect(find.text('Parabéns! Sua turma está em 1º lugar.'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedProgressPill>(
            find.byKey(const Key('ranking-hero-progress')),
          )
          .value,
      1,
    );
  });

  testWidgets('two classes fill two podium places safely', (tester) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (currentClassId) async => ranking([
          entry('class-a', 'Turma A', 9000),
          entry('class-current', 'Turma Atual', 5000),
        ], currentClassId: currentClassId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2º lugar'), findsOneWidget);
    expect(find.text('2º'), findsOneWidget);
    expect(find.text('9.000 XP'), findsOneWidget);
    expect(find.text('5.000 XP'), findsNWidgets(2));
    expect(find.text('Turma —'), findsOneWidget);
    expect(
      find.text('Faltam 4.000 XP para chegar ao 1º lugar.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedProgressPill>(
            find.byKey(const Key('ranking-hero-progress')),
          )
          .value,
      closeTo(5000 / 9000, 0.000001),
    );
  });

  testWidgets('three classes fill the complete podium', (tester) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (currentClassId) async => ranking([
          entry('class-a', 'Turma A', 9000),
          entry('class-current', 'Turma Atual', 5000),
          entry('class-c', 'Turma C', 1000),
        ], currentClassId: currentClassId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turma A'), findsOneWidget);
    expect(find.text('Turma Atual'), findsOneWidget);
    expect(find.text('Turma C'), findsOneWidget);
    expect(find.text('Turma —'), findsNothing);
  });

  testWidgets('more than three classes use only top three in podium', (
    tester,
  ) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (currentClassId) async => ranking([
          entry('class-a', 'Turma A', 9000),
          entry('class-b', 'Turma B', 7000),
          entry('class-c', 'Turma C', 5000),
          entry('class-current', 'Turma Atual', 3000),
        ], currentClassId: currentClassId),
      ),
    );
    await tester.pumpAndSettle();

    final hero = find.byKey(const Key('ranking-hero'));
    final podium = find.byKey(const Key('ranking-podium'));
    expect(find.text('4º lugar'), findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.text('3.000 XP')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: podium, matching: find.text('Turma Atual')),
      findsNothing,
    );
    expect(find.text('Turma A'), findsOneWidget);
    expect(find.text('Turma B'), findsOneWidget);
    expect(find.text('Turma C'), findsOneWidget);
    expect(find.text('Próxima meta: 5000 pontos para o top 3'), findsNothing);
    expect(
      find.text('Faltam 6.000 XP para chegar ao 1º lugar.'),
      findsOneWidget,
    );
    expect(find.text('76.000 pts'), findsNothing);
    expect(find.text('5.000 pontos'), findsNothing);
  });

  testWidgets('positive XP tie shows complete progress without zero distance', (
    tester,
  ) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (currentClassId) async => ranking([
          entry('class-a', 'Turma A', 9000),
          entry('class-current', 'Turma Atual', 9000),
        ], currentClassId: currentClassId),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Sua turma está empatada em pontos com o 1º lugar.'),
      findsOneWidget,
    );
    expect(find.textContaining('Faltam 0 XP'), findsNothing);
    expect(
      tester
          .widget<AnimatedProgressPill>(
            find.byKey(const Key('ranking-hero-progress')),
          )
          .value,
      1,
    );
    expect(find.text('Turma A'), findsOneWidget);
    expect(find.text('Turma Atual'), findsOneWidget);
  });

  testWidgets('zero-XP leader uses a neutral zero progress state', (
    tester,
  ) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (currentClassId) async => ranking([
          entry('class-a', 'Turma A', 0),
          entry('class-current', 'Turma Atual', 0),
        ], currentClassId: currentClassId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ainda não há XP para comparar.'), findsOneWidget);
    expect(find.textContaining('Faltam 0 XP'), findsNothing);
    expect(
      tester
          .widget<AnimatedProgressPill>(
            find.byKey(const Key('ranking-hero-progress')),
          )
          .value,
      0,
    );
    expect(find.text('0 XP'), findsNWidgets(3));
  });

  testWidgets('remote failure never activates pilot ranking', (tester) async {
    _configureSurface(tester);
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (_) async => throw const RankingFailure(
          RankingFailureKind.network,
          'Sem conexão com o Ranking.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão'), findsOneWidget);
    expect(find.text('Sem conexão com o Ranking.'), findsOneWidget);
    expect(find.text('7ºA'), findsNothing);
    expect(find.text('124.000 pts'), findsNothing);
  });

  testWidgets('session invalid triggers the standard invalid-session flow', (
    tester,
  ) async {
    _configureSurface(tester);
    var invalidations = 0;
    await _pumpAuthenticatedRanking(
      tester,
      _FakeRankingRepository(
        (_) async => throw const RankingFailure(
          RankingFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
        ),
      ),
      onSessionInvalid: () async => invalidations++,
    );
    await tester.pumpAndSettle();

    expect(find.text('Sessão expirada'), findsOneWidget);
    expect(invalidations, 1);
  });
}
