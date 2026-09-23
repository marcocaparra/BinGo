class BinBazarReward {
  const BinBazarReward({
    required this.id,
    required this.name,
    required this.description,
    required this.costPoints,
    required this.isActive,
    required this.stockQty,
  });

  final String id;
  final String name;
  final String? description;
  final int costPoints;
  final bool isActive;
  final int? stockQty;

  bool get isInStock => stockQty == null || stockQty! > 0;
  bool canRedeem(int balance) => isActive && isInStock && balance >= costPoints;
}

class BinBazarRedemption {
  const BinBazarRedemption({
    required this.id,
    required this.rewardId,
    required this.rewardName,
    required this.costPoints,
    required this.code,
    required this.status,
    required this.requestChannel,
    required this.createdAt,
    required this.deliveredAt,
    required this.canceledAt,
  });

  final String id;
  final String rewardId;
  final String rewardName;
  final int costPoints;
  final String code;
  final String status;
  final String requestChannel;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? canceledAt;

  bool get canCancel => status == 'PENDING';
}

class BinCoinStatementMovement {
  const BinCoinStatementMovement({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.amount,
    required this.title,
    required this.redemptionId,
    required this.sourceId,
  });

  final String id;
  final DateTime occurredAt;
  final String type;
  final int amount;
  final String title;
  final String? redemptionId;
  final String sourceId;

  bool get isCredit => amount > 0;
}

class RedemptionMutation {
  const RedemptionMutation({
    required this.redemption,
    required this.pointsStudentBalance,
    required this.replayed,
  });

  final BinBazarRedemption redemption;
  final int pointsStudentBalance;
  final bool replayed;
}

enum BinBazarFailureKind {
  network,
  sessionInvalid,
  conflict,
  rejected,
  malformedData,
  unknown,
}

class BinBazarFailure implements Exception {
  const BinBazarFailure(this.kind, this.message, [this.cause]);

  final BinBazarFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedBinBazarRepository {
  Future<List<BinBazarReward>> loadCatalog();

  Future<List<BinBazarRedemption>> loadRedemptions();

  Future<List<BinCoinStatementMovement>> loadStatement();

  Future<RedemptionMutation> requestRedemption({
    required String clientRequestId,
    required String rewardId,
  });

  Future<RedemptionMutation> cancelRedemption({required String redemptionId});
}

class EmptyAuthenticatedBinBazarRepository
    implements AuthenticatedBinBazarRepository {
  const EmptyAuthenticatedBinBazarRepository();

  @override
  Future<List<BinBazarReward>> loadCatalog() async => const [];

  @override
  Future<List<BinBazarRedemption>> loadRedemptions() async => const [];

  @override
  Future<List<BinCoinStatementMovement>> loadStatement() async => const [];

  @override
  Future<RedemptionMutation> requestRedemption({
    required String clientRequestId,
    required String rewardId,
  }) {
    throw const BinBazarFailure(
      BinBazarFailureKind.unknown,
      'O BinBazar autenticado não está disponível neste contexto.',
    );
  }

  @override
  Future<RedemptionMutation> cancelRedemption({required String redemptionId}) {
    throw const BinBazarFailure(
      BinBazarFailureKind.unknown,
      'O BinBazar autenticado não está disponível neste contexto.',
    );
  }
}
