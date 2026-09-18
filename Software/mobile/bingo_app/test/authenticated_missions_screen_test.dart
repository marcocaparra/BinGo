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
  schoolName: 'Escola BinGo',
  classId: 'class-id',
  className: '7º B',
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

class _FakeMissionsRepository implements AuthenticatedMissionsRepository {
  _FakeMissionsRepository(this.load);

  final Future<List<AuthenticatedMission>> Function() load;
  int calls = 0;

  @override
  Future<List<AuthenticatedMission>> loadActiveMissions() {
    calls++;
    return load();
  }
}

AuthenticatedMission mission({
  required String cycleId,
  required String title,
  required AuthenticatedMissionScope scope,
  int target = 10,
  int progress = 4,
  int rewardBinCoins = 500,
  int rewardXp = 0,
  bool isAchieved = false,
  bool isCompleted = false,
}) {
  return AuthenticatedMission(
    cycleId: cycleId,
    definitionId: 'definition-$cycleId',
    definitionCode: 'CODE_$cycleId',
    definitionTitle: title,
    scope: scope,
    metric: scope == AuthenticatedMissionScope.student
        ? AuthenticatedMissionMetric.validDepositCount
        : AuthenticatedMissionMetric.classXpEarned,
    startsAt: DateTime.utc(2026, 9),
    endsAt: DateTime.utc(2026, 10),
    target: target,
    rewardBinCoins: rewardBinCoins,
    rewardXp: rewardXp,
    progress: progress,
    isAchieved: isAchieved,
    achievedAt: isAchieved ? DateTime.utc(2026, 9, 12) : null,
    isCompleted: isCompleted,
    materializedAt: isCompleted ? DateTime.utc(2026, 9, 12, 1) : null,
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

Future<void> _pumpAuthenticatedMissions(
  WidgetTester tester,
  AuthenticatedMissionsRepository repository, {
  Future<void> Function()? onSessionInvalid,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ShellScreen.authenticated(
        initialIndex: 2,
        repository: const _StaticProfileRepository(),
        depositHistoryRepository: const _EmptyDepositHistoryRepository(),
        missionsRepository: repository,
        onLogout: () async => null,
        onSessionInvalid: onSessionInvalid ?? () async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('authenticated missions screen exposes loading', (tester) async {
    _configureSurface(tester);
    final pending = Completer<List<AuthenticatedMission>>();

    await _pumpAuthenticatedMissions(
      tester,
      _FakeMissionsRepository(() => pending.future),
    );

    expect(find.text('Carregando missões'), findsOneWidget);
    pending.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'authenticated missions screen exposes empty state without mocks',
    (tester) async {
      _configureSurface(tester);

      await _pumpAuthenticatedMissions(
        tester,
        _FakeMissionsRepository(() async => const []),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma missão ativa'), findsOneWidget);
      expect(find.text('Descarte corretamente 1 eletrônico'), findsNothing);
    },
  );

  testWidgets('renders STUDENT, CLASS, achieved and completed backend states', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeMissionsRepository(
      () async => [
        mission(
          cycleId: 'student',
          title: 'Consistência Sustentável',
          scope: AuthenticatedMissionScope.student,
          target: 10,
          progress: 17,
          isAchieved: true,
        ),
        mission(
          cycleId: 'class',
          title: 'Juntos pela Praça',
          scope: AuthenticatedMissionScope.classGroup,
          target: 10000,
          progress: 10000,
          rewardBinCoins: 0,
          rewardXp: 1900,
          isAchieved: true,
          isCompleted: true,
        ),
      ],
    );

    await _pumpAuthenticatedMissions(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Consistência Sustentável'), findsOneWidget);
    expect(find.text('Missão individual'), findsOneWidget);
    expect(find.text('17 / 10'), findsOneWidget);
    expect(find.text('+500 BinCoins'), findsOneWidget);
    expect(find.text('Meta atingida'), findsOneWidget);
    expect(find.text('Juntos pela Praça'), findsOneWidget);
    expect(find.text('Missão da turma'), findsOneWidget);
    expect(find.text('10000 / 10000'), findsOneWidget);
    expect(find.text('+1900 XP'), findsOneWidget);
    expect(find.text('Concluída'), findsOneWidget);
  });

  testWidgets('remote error never activates pilot missions', (tester) async {
    _configureSurface(tester);
    final repository = _FakeMissionsRepository(
      () async => throw const MissionsFailure(
        MissionsFailureKind.network,
        'Sem conexão com as missões.',
      ),
    );

    await _pumpAuthenticatedMissions(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão'), findsOneWidget);
    expect(find.text('Sem conexão com as missões.'), findsOneWidget);
    expect(find.text('Descarte corretamente 1 eletrônico'), findsNothing);
  });

  testWidgets('session invalid triggers the existing invalid-session flow', (
    tester,
  ) async {
    _configureSurface(tester);
    var invalidations = 0;
    final repository = _FakeMissionsRepository(
      () async => throw const MissionsFailure(
        MissionsFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      ),
    );

    await _pumpAuthenticatedMissions(
      tester,
      repository,
      onSessionInvalid: () async => invalidations++,
    );
    await tester.pumpAndSettle();

    expect(find.text('Sessão expirada'), findsOneWidget);
    expect(invalidations, 1);
  });

  testWidgets('pilot missions remain isolated and unchanged', (tester) async {
    _configureSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ShellScreen(initialIndex: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Descarte corretamente 1 eletrônico'), findsOneWidget);
    expect(find.text('Consistência Sustentável'), findsNothing);
  });
}
