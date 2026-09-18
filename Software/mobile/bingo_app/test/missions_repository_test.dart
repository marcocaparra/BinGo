import 'package:bingo_app/src/auth/supabase_auth_gateway.dart';
import 'package:bingo_app/src/data/missions_repository.dart';
import 'package:bingo_app/src/data/supabase_missions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeMissionsDataSource implements MissionsDataSource {
  _FakeMissionsDataSource({
    this.hasSession = true,
    this.rows = const [],
    this.error,
  });

  @override
  final bool hasSession;
  final List<Map<String, dynamic>> rows;
  final Object? error;
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchActiveMissions() async {
    calls++;
    if (error != null) throw error!;
    return rows;
  }
}

Map<String, dynamic> missionRow({
  String cycleId = 'cycle-id',
  String scope = 'STUDENT',
  String metric = 'VALID_DEPOSIT_COUNT',
  Object? target = 10,
  Object? rewardBinCoins = 500,
  Object? rewardXp = 0,
  Object? progress = 4,
  Object? isAchieved = false,
  Object? achievedAt,
  Object? isCompleted = false,
  Object? materializedAt,
}) {
  return <String, dynamic>{
    'cycle_id': cycleId,
    'definition_id': 'definition-id',
    'definition_code': 'CONSISTENCIA_SUSTENTAVEL',
    'definition_title': 'Consistência Sustentável',
    'scope': scope,
    'metric': metric,
    'starts_at': '2026-09-01T03:00:00Z',
    'ends_at': '2026-10-01T03:00:00Z',
    'target': target,
    'reward_bincoins': rewardBinCoins,
    'reward_xp': rewardXp,
    'progress': progress,
    'is_achieved': isAchieved,
    'achieved_at': achievedAt,
    'is_completed': isCompleted,
    'materialized_at': materializedAt,
  };
}

void main() {
  test(
    'Supabase source calls get_active_missions_v1 without identity params',
    () async {
      String? calledFunction;
      var calls = 0;
      final source = SupabaseMissionsDataSource(
        SupabaseClient('https://example.test', 'test-publishable-key'),
        rpcInvoker: (functionName) async {
          calledFunction = functionName;
          calls++;
          return <Map<String, dynamic>>[];
        },
      );

      final rows = await source.fetchActiveMissions();

      expect(rows, isEmpty);
      expect(calledFunction, 'get_active_missions_v1');
      expect(calls, 1);
    },
  );

  test('parses STUDENT and nullable completion timestamps', () async {
    final repository = RemoteMissionsRepository(
      _FakeMissionsDataSource(rows: [missionRow()]),
    );

    final mission = (await repository.loadActiveMissions()).single;

    expect(mission.scope, AuthenticatedMissionScope.student);
    expect(mission.metric, AuthenticatedMissionMetric.validDepositCount);
    expect(mission.achievedAt, isNull);
    expect(mission.materializedAt, isNull);
    expect(mission.rewardXp, 0);
  });

  test('parses CLASS and preserves zero BinCoins reward', () async {
    final repository = RemoteMissionsRepository(
      _FakeMissionsDataSource(
        rows: [
          missionRow(
            scope: 'CLASS',
            metric: 'CLASS_XP_EARNED',
            rewardBinCoins: 0,
            rewardXp: 1900,
          ),
        ],
      ),
    );

    final mission = (await repository.loadActiveMissions()).single;

    expect(mission.scope, AuthenticatedMissionScope.classGroup);
    expect(mission.metric, AuthenticatedMissionMetric.classXpEarned);
    expect(mission.rewardBinCoins, 0);
    expect(mission.rewardXp, 1900);
  });

  test(
    'preserves progress above target and backend completion state',
    () async {
      final repository = RemoteMissionsRepository(
        _FakeMissionsDataSource(
          rows: [
            missionRow(
              target: 10,
              progress: 17,
              isAchieved: true,
              achievedAt: '2026-09-12T10:00:00Z',
              isCompleted: true,
              materializedAt: '2026-09-12T10:01:00Z',
            ),
          ],
        ),
      );

      final mission = (await repository.loadActiveMissions()).single;

      expect(mission.progress, 17);
      expect(mission.target, 10);
      expect(mission.isAchieved, isTrue);
      expect(mission.isCompleted, isTrue);
      expect(mission.achievedAt, DateTime.parse('2026-09-12T10:00:00Z'));
      expect(mission.materializedAt, DateTime.parse('2026-09-12T10:01:00Z'));
    },
  );

  test('returns an empty immutable list without pilot fallback', () async {
    final source = _FakeMissionsDataSource();
    final missions = await RemoteMissionsRepository(
      source,
    ).loadActiveMissions();

    expect(missions, isEmpty);
    expect(source.calls, 1);
    expect(() => missions.add(_unusedMission), throwsUnsupportedError);
  });

  test('rejects loading without an authenticated session', () async {
    await expectLater(
      RemoteMissionsRepository(
        _FakeMissionsDataSource(hasSession: false),
      ).loadActiveMissions(),
      throwsA(
        isA<MissionsFailure>().having(
          (failure) => failure.kind,
          'kind',
          MissionsFailureKind.sessionInvalid,
        ),
      ),
    );
  });

  test('maps network failure without mock fallback', () async {
    await expectLater(
      RemoteMissionsRepository(
        _FakeMissionsDataSource(
          error: Exception('SocketException: connection refused'),
        ),
      ).loadActiveMissions(),
      throwsA(
        isA<MissionsFailure>().having(
          (failure) => failure.kind,
          'kind',
          MissionsFailureKind.network,
        ),
      ),
    );
  });

  test('rejects malformed payload instead of inventing values', () async {
    final malformedRows = [
      missionRow(target: '10'),
      missionRow(rewardBinCoins: 0, rewardXp: 0),
      missionRow(isAchieved: true, achievedAt: null),
      missionRow(scope: 'CLASS', metric: 'VALID_DEPOSIT_COUNT'),
    ];

    for (final row in malformedRows) {
      await expectLater(
        RemoteMissionsRepository(
          _FakeMissionsDataSource(rows: [row]),
        ).loadActiveMissions(),
        throwsA(
          isA<MissionsFailure>().having(
            (failure) => failure.kind,
            'kind',
            MissionsFailureKind.malformedData,
          ),
        ),
      );
    }
  });

  test(
    'SupabaseAuthGateway exposes the authenticated missions repository',
    () async {
      final gateway = SupabaseAuthGateway(
        SupabaseClient('https://example.test', 'test-publishable-key'),
      );
      addTearDown(gateway.close);

      expect(
        gateway.missionsRepository,
        isA<AuthenticatedMissionsRepository>(),
      );
    },
  );
}

final _unusedMission = AuthenticatedMission(
  cycleId: 'unused-cycle',
  definitionId: 'unused-definition',
  definitionCode: 'UNUSED',
  definitionTitle: 'Unused',
  scope: AuthenticatedMissionScope.student,
  metric: AuthenticatedMissionMetric.validDepositCount,
  startsAt: DateTime.utc(2026, 9),
  endsAt: DateTime.utc(2026, 10),
  target: 1,
  rewardBinCoins: 1,
  rewardXp: 0,
  progress: 0,
  isAchieved: false,
  achievedAt: null,
  isCompleted: false,
  materializedAt: null,
);
