import 'package:bingo_app/src/data/binbazar_repository.dart';
import 'package:bingo_app/src/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'authenticated BinBazar retries one intent, updates balance and cancels',
    (tester) async {
      final repository = _MutableBinBazarRepository(failFirstRequest: true);
      final mutations = <RedemptionMutation>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RewardsScreen.authenticated(
            balance: 1000,
            catalog: repository.catalog,
            redemptions: const [],
            repository: repository,
            loading: false,
            failure: null,
            onRetry: () {},
            onMutation: (mutation) async => mutations.add(mutation),
          ),
        ),
      );

      expect(find.text('Produto real da escola'), findsOneWidget);
      await _requestVisibleReward(tester);
      expect(find.text('Não foi possível concluir'), findsOneWidget);

      await _requestVisibleReward(tester);
      expect(repository.requestIds, hasLength(2));
      expect(repository.requestIds.toSet(), hasLength(1));
      expect(repository.lastRequestReplayed, isTrue);
      expect(find.text('Pedido confirmado'), findsOneWidget);
      expect(find.text('BGO-MOBILE'), findsWidgets);
      await tester.tapAt(const Offset(10, 10));
      await _pumpFrames(tester);

      expect(find.text('700'), findsWidgets);
      expect(find.text('Esgotado'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsOneWidget);
      await tester.tap(find.text('Cancelar pedido'));
      await _pumpFrames(tester);

      expect(find.text('1.000'), findsWidgets);
      expect(find.textContaining('Cancelado'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsNothing);
      expect(find.text('Solicitar resgate'), findsOneWidget);
      expect(mutations, hasLength(2));
    },
  );

  testWidgets('authenticated wallet renders consolidated real statement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen.authenticated(
          balance: 1200,
          catalog: const [
            BinBazarReward(
              id: 'remote-only',
              name: 'Produto remoto exclusivo',
              description: 'Somente o catálogo autenticado conhece este item.',
              costPoints: 2000,
              isActive: true,
              stockQty: 1,
            ),
          ],
          redemptions: const [],
          statement: [
            BinCoinStatementMovement(
              id: 'refund-1',
              occurredAt: _statementDate,
              type: 'REDEMPTION_REFUND',
              amount: 300,
              title: 'Produto fotografado',
              redemptionId: 'order-1',
              sourceId: 'order-1',
            ),
            BinCoinStatementMovement(
              id: 'redeem-1',
              occurredAt: _statementDate,
              type: 'REDEMPTION',
              amount: -300,
              title: 'Produto fotografado',
              redemptionId: 'order-1',
              sourceId: 'order-1',
            ),
          ],
          binBazarRepository: const EmptyAuthenticatedBinBazarRepository(),
          binBazarLoading: false,
          binBazarFailure: null,
          onRetryBinBazar: () {},
          onMutation: (_) async {},
          discards: const [],
          isLoading: false,
          historyFailure: null,
          onRetryHistory: () {},
        ),
      ),
    );

    expect(find.text('Estorno de resgate'), findsOneWidget);
    expect(find.text('Resgate'), findsOneWidget);
    expect(find.textContaining('Produto fotografado'), findsNWidgets(2));
    expect(find.text('Extrato indisponível'), findsNothing);
    expect(find.textContaining('simulação'), findsNothing);
    expect(find.textContaining('Suco natural'), findsNothing);
    expect(find.textContaining('Caneta temática'), findsNothing);
    expect(
      find.text('0 opções disponíveis no catálogo da sua escola'),
      findsOneWidget,
    );
  });
}

final _statementDate = DateTime.utc(2026, 9, 22, 12);

Future<void> _requestVisibleReward(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('reward-card-reward-1'));
  await tester.ensureVisible(card);
  await _pumpFrames(tester);
  await tester.tap(card);
  await _pumpFrames(tester);
  await tester.tap(find.text('Solicitar por 300 BinCoins'));
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _MutableBinBazarRepository implements AuthenticatedBinBazarRepository {
  _MutableBinBazarRepository({required this.failFirstRequest});

  final bool failFirstRequest;
  int requestCalls = 0;
  final List<String> requestIds = [];
  bool lastRequestReplayed = false;
  int _balance = 1000;
  BinBazarRedemption? _acceptedRedemption;
  String? _acceptedRequestId;

  List<BinBazarReward> catalog = const [
    BinBazarReward(
      id: 'reward-1',
      name: 'Produto real da escola',
      description: 'Catálogo autenticado',
      costPoints: 300,
      isActive: true,
      stockQty: 1,
    ),
  ];
  List<BinBazarRedemption> redemptions = [];

  @override
  Future<List<BinBazarReward>> loadCatalog() async => catalog;

  @override
  Future<List<BinBazarRedemption>> loadRedemptions() async => redemptions;

  @override
  Future<List<BinCoinStatementMovement>> loadStatement() async => const [];

  @override
  Future<RedemptionMutation> requestRedemption({
    required String clientRequestId,
    required String rewardId,
  }) async {
    requestCalls++;
    requestIds.add(clientRequestId);
    if (_acceptedRedemption == null) {
      _acceptedRequestId = clientRequestId;
      _acceptedRedemption = _redemption(status: 'PENDING');
      _balance = 700;
      catalog = [_rewardWithStock(0)];
      redemptions = [_acceptedRedemption!];
    }
    final replayed = _acceptedRequestId == clientRequestId && requestCalls > 1;
    lastRequestReplayed = replayed;
    if (failFirstRequest && requestCalls == 1) {
      throw const BinBazarFailure(
        BinBazarFailureKind.network,
        'Timeout após confirmação para testar retry.',
      );
    }
    return RedemptionMutation(
      redemption: _acceptedRedemption!,
      pointsStudentBalance: _balance,
      replayed: replayed,
    );
  }

  @override
  Future<RedemptionMutation> cancelRedemption({
    required String redemptionId,
  }) async {
    _acceptedRedemption = _redemption(status: 'CANCELED');
    redemptions = [_acceptedRedemption!];
    catalog = [_rewardWithStock(1)];
    _balance = 1000;
    return RedemptionMutation(
      redemption: _acceptedRedemption!,
      pointsStudentBalance: _balance,
      replayed: false,
    );
  }

  BinBazarReward _rewardWithStock(int stockQty) {
    return BinBazarReward(
      id: 'reward-1',
      name: 'Produto real da escola',
      description: 'Catálogo autenticado',
      costPoints: 300,
      isActive: true,
      stockQty: stockQty,
    );
  }
}

BinBazarRedemption _redemption({required String status}) {
  return BinBazarRedemption(
    id: 'order-1',
    rewardId: 'reward-1',
    rewardName: 'Produto real da escola',
    costPoints: 300,
    code: 'BGO-MOBILE',
    status: status,
    requestChannel: 'MOBILE',
    createdAt: _statementDate,
    deliveredAt: null,
    canceledAt: status == 'CANCELED' ? _statementDate : null,
  );
}
