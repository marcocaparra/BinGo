class DepositHistoryCategory {
  const DepositHistoryCategory({
    required this.id,
    required this.code,
    required this.displayName,
  });

  final String id;
  final String code;
  final String displayName;
}

class AuthenticatedDepositHistoryEntry {
  const AuthenticatedDepositHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.isValid,
    required this.detectedType,
    required this.category,
    required this.categorySource,
    required this.bonusBinCoinsAwarded,
    required this.pointsAwardedStudent,
    required this.pointsAwardedClass,
  });

  final String id;
  final DateTime createdAt;
  final bool isValid;
  final String? detectedType;
  final DepositHistoryCategory? category;
  final String? categorySource;
  final int bonusBinCoinsAwarded;
  final int pointsAwardedStudent;
  final int pointsAwardedClass;
}

enum DepositHistoryFailureKind {
  network,
  sessionInvalid,
  malformedData,
  unknown,
}

class DepositHistoryFailure implements Exception {
  const DepositHistoryFailure(this.kind, this.message, [this.cause]);

  final DepositHistoryFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedDepositHistoryRepository {
  Future<List<AuthenticatedDepositHistoryEntry>> loadHistory({
    required String studentId,
  });
}
