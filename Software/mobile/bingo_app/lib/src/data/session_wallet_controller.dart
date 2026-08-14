import 'package:flutter/foundation.dart';

import 'demo_data.dart';

class SessionWalletController extends ChangeNotifier {
  SessionWalletController({
    int initialBalance = userBinCoins,
    List<BinCoinTransaction> initialTransactions = binCoinTransactions,
  }) : _balance = initialBalance,
       _transactions = List.of(initialTransactions);

  int _balance;
  final List<BinCoinTransaction> _transactions;
  final List<RewardRedemption> _redemptions = [];
  int _sequence = 0;

  int get balance => _balance;
  List<BinCoinTransaction> get transactions => List.unmodifiable(_transactions);
  List<RewardRedemption> get redemptions => List.unmodifiable(_redemptions);

  RewardRedemption? redeem(RewardItem reward) {
    if (_balance < reward.cost) return null;
    _sequence += 1;
    _balance -= reward.cost;
    final suffix = ((_sequence * 137) + reward.cost)
        .toRadixString(36)
        .toUpperCase();
    final redemption = RewardRedemption(
      id: '${reward.id}-$_sequence',
      rewardId: reward.id,
      rewardTitle: reward.title,
      cost: reward.cost,
      pickupCode: 'BGO-${suffix.padLeft(3, '0')}',
      createdAt: DateTime.now(),
    );
    _redemptions.insert(0, redemption);
    _transactions.insert(
      0,
      BinCoinTransaction(
        title: 'Usou',
        subtitle: '${reward.title} resgatado no BinBazar',
        amount: reward.cost,
        kind: TransactionKind.debit,
      ),
    );
    notifyListeners();
    return redemption;
  }
}
