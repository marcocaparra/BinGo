import 'package:bingo_app/src/data/demo_data.dart';
import 'package:bingo_app/src/data/session_wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redeem debits balance and adds an extract entry and pickup code', () {
    final controller = SessionWalletController();
    final redemption = controller.redeem(rewards.first);

    expect(redemption, isNotNull);
    expect(controller.balance, 90);
    expect(controller.transactions.first.subtitle, contains('Suco natural'));
    expect(controller.transactions.first.kind, TransactionKind.debit);
    expect(redemption!.pickupCode, startsWith('BGO-'));
  });

  test('reward can be redeemed repeatedly while the session has balance', () {
    final controller = SessionWalletController();

    expect(controller.redeem(rewards.first), isNotNull);
    expect(controller.redeem(rewards.first), isNotNull);
    expect(controller.redeem(rewards.first), isNotNull);
    expect(controller.redeem(rewards.first), isNotNull);
    expect(controller.balance, 0);
    expect(controller.redeem(rewards.first), isNull);
    expect(controller.redemptions, hasLength(4));
  });

  test('a new controller restores the demonstration defaults', () {
    final changed = SessionWalletController()..redeem(rewards.first);
    final restarted = SessionWalletController();

    expect(changed.balance, 90);
    expect(restarted.balance, userBinCoins);
    expect(restarted.redemptions, isEmpty);
    expect(restarted.transactions, binCoinTransactions);
  });
}
