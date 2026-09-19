import 'dart:async';

import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/ranking_repository.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:bingo_app/src/theme/app_assets.dart';
import 'package:bingo_app/src/theme/app_theme.dart';
import 'package:bingo_app/src/widgets/bingo_widgets.dart';
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
  DateTime? startsAt,
  String? definitionCode,
}) {
  return AuthenticatedMission(
    cycleId: cycleId,
    definitionId: 'definition-$cycleId',
    definitionCode: definitionCode ?? 'CODE_$cycleId',
    definitionTitle: title,
    scope: scope,
    metric: scope == AuthenticatedMissionScope.student
        ? AuthenticatedMissionMetric.validDepositCount
        : AuthenticatedMissionMetric.classXpEarned,
    startsAt: startsAt ?? DateTime.utc(2026, 9),
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
        rankingRepository: const _EmptyRankingRepository(),
        onLogout: () async => null,
        onSessionInvalid: onSessionInvalid ?? () async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _EmptyRankingRepository implements AuthenticatedRankingRepository {
  const _EmptyRankingRepository();

  @override
  Future<ClassRanking> loadRanking({required String currentClassId}) async {
    return const ClassRanking(entries: [], currentClassIndex: null);
  }
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

      expect(find.text('Missões de restauração'), findsOneWidget);
      expect(
        find.text('Acompanhe metas seguras e o progresso da sua turma.'),
        findsOneWidget,
      );
      expect(find.text('Força-tarefa em destaque'), findsOneWidget);
      expect(find.text('Outras etapas da jornada'), findsOneWidget);
      expect(find.text('Nenhuma missão individual ativa'), findsOneWidget);
      expect(find.text('Nenhuma missão coletiva ativa'), findsOneWidget);
      expect(find.text('Ainda não há outras etapas'), findsOneWidget);
      expect(find.text('Descarte corretamente 1 eletrônico'), findsNothing);
    },
  );

  testWidgets('classifies real missions into the canonical pilot composition', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeMissionsRepository(
      () async => [
        mission(
          cycleId: 'class-active',
          title: 'Juntos pela Praça',
          scope: AuthenticatedMissionScope.classGroup,
          target: 10000,
          progress: 4300,
          rewardBinCoins: 0,
          rewardXp: 1900,
        ),
        mission(
          cycleId: 'completed',
          title: 'Primeiro descarte sustentável',
          scope: AuthenticatedMissionScope.student,
          target: 1,
          progress: 1,
          rewardBinCoins: 100,
          isAchieved: true,
          isCompleted: true,
        ),
        mission(
          cycleId: 'student',
          title: 'Consistência Sustentável',
          scope: AuthenticatedMissionScope.student,
          target: 10,
          progress: 17,
          rewardXp: 700,
          isAchieved: true,
        ),
      ],
    );

    await _pumpAuthenticatedMissions(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Missões de restauração'), findsOneWidget);
    expect(
      find.text('Acompanhe metas seguras e o progresso da sua turma.'),
      findsOneWidget,
    );
    expect(find.text('Escola BinGo · 7º B'), findsNothing);

    final hero = find.byKey(const Key('missions-featured-hero'));
    final collective = find.byKey(
      const ValueKey('missions-collective-class-active'),
    );
    final completed = find.byKey(const ValueKey('missions-journey-completed'));

    expect(hero, findsOneWidget);
    expect(
      find.descendant(
        of: hero,
        matching: find.text('Consistência Sustentável'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.text('Juntos pela Praça')),
      findsNothing,
    );
    expect(find.text('Meta atingida'), findsOneWidget);

    expect(find.text('Força-tarefa em destaque'), findsOneWidget);
    expect(collective, findsOneWidget);
    expect(
      find.descendant(of: collective, matching: find.text('Juntos pela Praça')),
      findsOneWidget,
    );
    expect(find.textContaining('4300 / 10000'), findsOneWidget);
    expect(find.text('+1900 XP'), findsOneWidget);

    expect(find.text('Outras etapas da jornada'), findsOneWidget);
    expect(completed, findsOneWidget);
    expect(
      find.descendant(
        of: completed,
        matching: find.text('Primeiro descarte sustentável'),
      ),
      findsOneWidget,
    );
    expect(find.text('+100 BinCoins'), findsOneWidget);
    expect(find.text('Concluída'), findsOneWidget);

    expect(find.text('+500 BinCoins · +700 XP'), findsOneWidget);
    expect(find.text('5 descartes validados até sexta.'), findsNothing);
    expect(find.text('+20 bônus'), findsNothing);

    expect(
      find.descendant(
        of: hero,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == AppAssets.sceneClean,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  AppAssets.b1nMissionReady,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: collective,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is BingoAssetImage &&
              widget.asset == AppAssets.scr4pDefense &&
              widget.fit == BoxFit.contain &&
              widget.alignment == Alignment.bottomCenter &&
              widget.filterQuality == FilterQuality.high,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(hero);
    await tester.pumpAndSettle();
    expect(find.text('Missão'), findsOneWidget);
    expect(find.text('Dados simulados'), findsNothing);
    expect(find.text('+500 BinCoins · +700 XP'), findsWidgets);
  });

  testWidgets('uses deterministic dates instead of RPC order for the hero', (
    tester,
  ) async {
    _configureSurface(tester);
    final repository = _FakeMissionsRepository(
      () async => [
        mission(
          cycleId: 'later',
          title: 'Missão individual posterior',
          scope: AuthenticatedMissionScope.student,
          startsAt: DateTime.utc(2026, 9, 10),
        ),
        mission(
          cycleId: 'earlier',
          title: 'Missão individual prioritária',
          scope: AuthenticatedMissionScope.student,
          startsAt: DateTime.utc(2026, 9, 1),
        ),
      ],
    );

    await _pumpAuthenticatedMissions(tester, repository);
    await tester.pumpAndSettle();

    final hero = find.byKey(const Key('missions-featured-hero'));
    expect(
      find.descendant(
        of: hero,
        matching: find.text('Missão individual prioritária'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('missions-journey-later')),
      findsOneWidget,
    );
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
