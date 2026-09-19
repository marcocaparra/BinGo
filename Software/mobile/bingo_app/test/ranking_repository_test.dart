import 'package:bingo_app/src/auth/supabase_auth_gateway.dart';
import 'package:bingo_app/src/data/ranking_repository.dart';
import 'package:bingo_app/src/data/supabase_ranking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRankingDataSource implements RankingDataSource {
  _FakeRankingDataSource({
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
  Future<List<Map<String, dynamic>>> fetchRanking() async {
    calls++;
    if (error != null) throw error!;
    return rows;
  }
}

Map<String, dynamic> rankingRow({
  required String id,
  required String name,
  required Object? balance,
}) {
  return {'class_id': id, 'class_name': name, 'points_class_balance': balance};
}

void main() {
  test('Supabase source calls get_class_ranking_v1 without params', () async {
    String? calledFunction;
    var calls = 0;
    final source = SupabaseRankingDataSource(
      SupabaseClient('https://example.test', 'test-publishable-key'),
      rpcInvoker: (functionName) async {
        calledFunction = functionName;
        calls++;
        return <Map<String, dynamic>>[];
      },
    );

    final rows = await source.fetchRanking();

    expect(rows, isEmpty);
    expect(calledFunction, 'get_class_ranking_v1');
    expect(calls, 1);
  });

  test(
    'maps ordered rows and locates current class in the same list',
    () async {
      final source = _FakeRankingDataSource(
        rows: [
          rankingRow(id: 'a-class', name: '7º A', balance: 9000),
          rankingRow(id: 'b-class', name: '8º B', balance: 5000),
          rankingRow(id: 'c-class', name: '9º C', balance: 0),
        ],
      );

      final ranking = await RemoteRankingRepository(
        source,
      ).loadRanking(currentClassId: 'b-class');

      expect(ranking.entries, hasLength(3));
      expect(ranking.currentClass?.className, '8º B');
      expect(ranking.currentClass?.pointsClassBalance, 5000);
      expect(ranking.currentPosition, 2);
      expect(ranking.topThree.map((entry) => entry.classId), [
        'a-class',
        'b-class',
        'c-class',
      ]);
      expect(source.calls, 1);
    },
  );

  test('empty ranking is valid and never activates demo data', () async {
    final ranking = await RemoteRankingRepository(
      _FakeRankingDataSource(),
    ).loadRanking(currentClassId: 'current-class');

    expect(ranking.entries, isEmpty);
    expect(ranking.currentClass, isNull);
    expect(ranking.currentPosition, isNull);
    expect(ranking.topThree, isEmpty);
    expect(
      () => ranking.entries.add(
        const ClassRankingEntry(
          classId: 'demo',
          className: 'Demo',
          pointsClassBalance: 1,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('topThree safely limits lists longer than three', () async {
    final ranking = await RemoteRankingRepository(
      _FakeRankingDataSource(
        rows: [
          rankingRow(id: 'a', name: 'A', balance: 40),
          rankingRow(id: 'b', name: 'B', balance: 30),
          rankingRow(id: 'c', name: 'C', balance: 20),
          rankingRow(id: 'd', name: 'D', balance: 10),
        ],
      ),
    ).loadRanking(currentClassId: 'd');

    expect(ranking.topThree.map((entry) => entry.classId), ['a', 'b', 'c']);
    expect(ranking.currentPosition, 4);
  });

  test('rejects nonempty response without the current class', () async {
    await expectLater(
      RemoteRankingRepository(
        _FakeRankingDataSource(
          rows: [rankingRow(id: 'other', name: 'Outra', balance: 10)],
        ),
      ).loadRanking(currentClassId: 'current'),
      throwsA(
        isA<RankingFailure>().having(
          (failure) => failure.kind,
          'kind',
          RankingFailureKind.malformedData,
        ),
      ),
    );
  });

  test('rejects malformed, duplicated or incorrectly ordered rows', () async {
    final invalidRows = <List<Map<String, dynamic>>>[
      [rankingRow(id: 'a', name: 'A', balance: -1)],
      [rankingRow(id: 'a', name: '', balance: 1)],
      [
        rankingRow(id: 'a', name: 'A', balance: 1),
        rankingRow(id: 'b', name: 'B', balance: 2),
      ],
      [
        rankingRow(id: 'b', name: 'B', balance: 2),
        rankingRow(id: 'a', name: 'A', balance: 2),
      ],
      [
        rankingRow(id: 'a', name: 'A', balance: 2),
        rankingRow(id: 'a', name: 'A', balance: 1),
      ],
    ];

    for (final rows in invalidRows) {
      await expectLater(
        RemoteRankingRepository(
          _FakeRankingDataSource(rows: rows),
        ).loadRanking(currentClassId: 'a'),
        throwsA(
          isA<RankingFailure>().having(
            (failure) => failure.kind,
            'kind',
            RankingFailureKind.malformedData,
          ),
        ),
      );
    }
  });

  test('rejects loading without an authenticated session', () async {
    await expectLater(
      RemoteRankingRepository(
        _FakeRankingDataSource(hasSession: false),
      ).loadRanking(currentClassId: 'current'),
      throwsA(
        isA<RankingFailure>().having(
          (failure) => failure.kind,
          'kind',
          RankingFailureKind.sessionInvalid,
        ),
      ),
    );
  });

  test('maps network failure without demo fallback', () async {
    await expectLater(
      RemoteRankingRepository(
        _FakeRankingDataSource(
          error: Exception('SocketException: connection refused'),
        ),
      ).loadRanking(currentClassId: 'current'),
      throwsA(
        isA<RankingFailure>().having(
          (failure) => failure.kind,
          'kind',
          RankingFailureKind.network,
        ),
      ),
    );
  });

  test('SupabaseAuthGateway exposes authenticated ranking repository', () {
    final gateway = SupabaseAuthGateway(
      SupabaseClient('https://example.test', 'test-publishable-key'),
    );
    addTearDown(gateway.close);

    expect(gateway.rankingRepository, isA<AuthenticatedRankingRepository>());
  });
}
