import 'package:bingo_app/src/data/class_journey_repository.dart';
import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/ranking_repository.dart';
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
  className: '7º A',
  pointsStudentBalance: 1200,
  pointsClassBalance: 1900,
  status: 'ACTIVE',
  progress: AuthenticatedProfileProgress(
    studentId: 'student-id',
    validDepositCount: 8,
    levelNumber: 2,
    levelCode: 'EXPLORER',
    remainingToNextLevel: 2,
    progressToNextLevel: 0.8,
  ),
);

final _journey = AuthenticatedClassJourney(
  campaignId: 'campaign-id',
  startsAt: DateTime.utc(2026, 7, 1, 3),
  endsAt: DateTime.utc(2027, 1, 1, 3),
  totalUnits: 27,
  validDepositCount: 19,
  studentMissionCompletionCount: 1,
  classMissionCompletionCount: 1,
  stages: const [
    AuthenticatedJourneyStage(
      code: JourneyStageCode.centralSquare,
      order: 1,
      targetUnits: 20,
      progressUnits: 20,
      progressRatio: 1,
      state: JourneyStageState.completed,
      remainingUnits: 0,
    ),
    AuthenticatedJourneyStage(
      code: JourneyStageCode.springPark,
      order: 2,
      targetUnits: 25,
      progressUnits: 7,
      progressRatio: 0.28,
      state: JourneyStageState.active,
      remainingUnits: 18,
    ),
    AuthenticatedJourneyStage(
      code: JourneyStageCode.creativeSchool,
      order: 3,
      targetUnits: 30,
      progressUnits: 0,
      progressRatio: 0,
      state: JourneyStageState.locked,
      remainingUnits: 30,
    ),
  ],
);

class _ProfileRepository implements AuthenticatedProfileRepository {
  const _ProfileRepository();

  @override
  Future<AuthenticatedStudentProfile> loadProfile() async => _profile;
}

class _JourneyRepository implements AuthenticatedClassJourneyRepository {
  var calls = 0;

  @override
  Future<AuthenticatedClassJourney?> loadJourney() async {
    calls++;
    return _journey;
  }
}

class _HistoryRepository implements AuthenticatedDepositHistoryRepository {
  const _HistoryRepository();

  @override
  Future<List<AuthenticatedDepositHistoryEntry>> loadHistory({
    required String studentId,
  }) async => const [];
}

class _MissionsRepository implements AuthenticatedMissionsRepository {
  const _MissionsRepository();

  @override
  Future<List<AuthenticatedMission>> loadActiveMissions() async => [
    AuthenticatedMission(
      cycleId: 'cycle-id',
      definitionId: 'definition-id',
      definitionCode: 'ONE_VALID_DEPOSIT',
      definitionTitle: 'Faça um descarte consciente',
      scope: AuthenticatedMissionScope.student,
      metric: AuthenticatedMissionMetric.validDepositCount,
      startsAt: DateTime.utc(2026, 9, 1, 3),
      endsAt: DateTime.utc(2026, 10, 1, 3),
      target: 1,
      rewardBinCoins: 100,
      rewardXp: 0,
      progress: 0,
      isAchieved: false,
      achievedAt: null,
      isCompleted: false,
      materializedAt: null,
    ),
  ];
}

class _RankingRepository implements AuthenticatedRankingRepository {
  const _RankingRepository();

  @override
  Future<ClassRanking> loadRanking({required String currentClassId}) async {
    return ClassRanking(
      entries: const [
        ClassRankingEntry(
          classId: 'class-id',
          className: '7º A',
          pointsClassBalance: 1900,
        ),
      ],
      currentClassIndex: 0,
    );
  }
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

Future<_JourneyRepository> _pumpShell(
  WidgetTester tester, {
  int initialIndex = 0,
}) async {
  final journeyRepository = _JourneyRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ShellScreen.authenticated(
        initialIndex: initialIndex,
        repository: const _ProfileRepository(),
        depositHistoryRepository: const _HistoryRepository(),
        missionsRepository: const _MissionsRepository(),
        journeyRepository: journeyRepository,
        rankingRepository: const _RankingRepository(),
        onLogout: () async => null,
        onSessionInvalid: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return journeyRepository;
}

void main() {
  testWidgets('Home uses real Journey and opens the authenticated map', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = await _pumpShell(tester);

    expect(repository.calls, 1);
    expect(
      find.text('Sua turma está restaurando a Parque das Nascentes.'),
      findsOneWidget,
    );
    expect(find.text('Parque das Nascentes'), findsOneWidget);
    expect(find.text('28% restaurada'), findsOneWidget);
    expect(find.text('Faltam 18 para o próximo setor'), findsOneWidget);
    expect(find.text('Faça um descarte consciente'), findsOneWidget);
    expect(find.textContaining('Escola BinGo · 7º A'), findsNothing);

    await tester.tap(find.text('28% restaurada'));
    await tester.pumpAndSettle();

    expect(find.text('BinGópolis'), findsOneWidget);
    expect(find.text('Dados da turma'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('advance-bingopolis-journey')),
      findsNothing,
    );
  });

  testWidgets('Ranking and map consume the same real Journey snapshot', (
    tester,
  ) async {
    _configureSurface(tester);
    await _pumpShell(tester, initialIndex: 3);

    expect(find.text('A jornada de restauração'), findsOneWidget);
    expect(
      find.text(
        'A Parque das Nascentes está em restauração. Faltam 18 para concluir este setor.',
      ),
      findsOneWidget,
    );

    final rankingList = find.ancestor(
      of: find.text('Ranking das turmas'),
      matching: find.byType(ListView),
    );
    await tester.drag(rankingList, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar BinGópolis'));
    await tester.pumpAndSettle();

    expect(find.text('Parque das Nascentes'), findsWidgets);
    expect(find.text('28% restaurada'), findsWidgets);
    expect(find.text('Dados da turma'), findsOneWidget);

    await tester.tap(find.text('Ver cenário'));
    await tester.pumpAndSettle();
    expect(find.text('progresso registrado'), findsOneWidget);
    expect(find.text('dias neste ciclo'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver impacto da turma'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A superfície de impacto está pronta para receber dados reais.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('3,2'), findsNothing);
  });
}
