import 'package:bingo_app/src/data/binbazar_repository.dart';
import 'package:bingo_app/src/data/supabase_binbazar_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository parses authenticated catalog, orders and statement',
    () async {
      final source = _FakeSource({
        RemoteBinBazarRepository.catalogRpc: [_rewardRow],
        RemoteBinBazarRepository.redemptionsRpc: [_redemptionRow],
        RemoteBinBazarRepository.statementRpc: [_movementRow],
      });
      final repository = RemoteBinBazarRepository(source);

      final catalog = await repository.loadCatalog();
      final redemptions = await repository.loadRedemptions();
      final statement = await repository.loadStatement();

      expect(catalog.single.name, 'Suco da escola');
      expect(catalog.single.stockQty, 2);
      expect(redemptions.single.rewardName, 'Nome fotografado');
      expect(redemptions.single.code, 'BGO-REAL');
      expect(redemptions.single.canCancel, isTrue);
      expect(statement.single.type, 'REDEMPTION');
      expect(statement.single.amount, -300);
    },
  );

  test(
    'repository sends the same supplied request id without generating one',
    () async {
      final source = _FakeSource({
        RemoteBinBazarRepository.requestRpc: [
          {
            ..._redemptionRow,
            'code': null,
            'points_student_balance': 700,
            'replayed': false,
          },
        ],
      });
      final repository = RemoteBinBazarRepository(source);

      final result = await repository.requestRedemption(
        clientRequestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        rewardId: 'reward-1',
      );

      expect(result.pointsStudentBalance, 700);
      expect(result.redemption.code, isNull);
      expect(source.lastParameters, {
        'p_request_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'p_reward_id': 'reward-1',
      });
    },
  );

  test('repository uses server balance after cancellation', () async {
    final source = _FakeSource({
      RemoteBinBazarRepository.cancelRpc: [
        {
          ..._redemptionRow,
          'code': null,
          'status': 'CANCELED',
          'canceled_at': '2026-09-22T12:00:00Z',
          'points_student_balance': 1000,
          'replayed': false,
        },
      ],
    });
    final repository = RemoteBinBazarRepository(source);

    final result = await repository.cancelRedemption(redemptionId: 'order-1');

    expect(result.pointsStudentBalance, 1000);
    expect(result.redemption.status, 'CANCELED');
    expect(result.redemption.code, isNull);
    expect(source.lastParameters, {'p_redemption_id': 'order-1'});
  });

  test('repository refuses calls without an authenticated session', () async {
    final repository = RemoteBinBazarRepository(
      _FakeSource({}, hasSession: false),
    );

    await expectLater(
      repository.loadCatalog(),
      throwsA(
        isA<BinBazarFailure>().having(
          (failure) => failure.kind,
          'kind',
          BinBazarFailureKind.sessionInvalid,
        ),
      ),
    );
  });
}

const _rewardRow = <String, dynamic>{
  'reward_id': 'reward-1',
  'name': 'Suco da escola',
  'description': 'Produto real',
  'cost_points': 300,
  'is_active': true,
  'stock_qty': 2,
};

const _redemptionRow = <String, dynamic>{
  'redemption_id': 'order-1',
  'reward_id': 'reward-1',
  'reward_name': 'Nome fotografado',
  'cost_points': 300,
  'code': 'BGO-REAL',
  'status': 'PENDING',
  'request_channel': 'MOBILE',
  'created_at': '2026-09-22T10:00:00Z',
  'delivered_at': null,
  'canceled_at': null,
};

const _movementRow = <String, dynamic>{
  'movement_id': 'REDEMPTION:order-1',
  'occurred_at': '2026-09-22T10:00:00Z',
  'movement_type': 'REDEMPTION',
  'amount': -300,
  'title': 'Nome fotografado',
  'redemption_id': 'order-1',
  'source_id': 'order-1',
};

class _FakeSource implements BinBazarDataSource {
  _FakeSource(this.responses, {this.hasSession = true});

  final Map<String, List<Map<String, dynamic>>> responses;

  @override
  final bool hasSession;

  Map<String, dynamic>? lastParameters;

  @override
  Future<List<Map<String, dynamic>>> invoke(
    String functionName, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    lastParameters = parameters;
    return responses[functionName] ?? const [];
  }
}
