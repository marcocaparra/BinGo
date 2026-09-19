class ClassRankingEntry {
  const ClassRankingEntry({
    required this.classId,
    required this.className,
    required this.pointsClassBalance,
  });

  final String classId;
  final String className;
  final int pointsClassBalance;
}

class ClassRanking {
  const ClassRanking({required this.entries, required this.currentClassIndex});

  final List<ClassRankingEntry> entries;
  final int? currentClassIndex;

  ClassRankingEntry? get currentClass =>
      currentClassIndex == null ? null : entries[currentClassIndex!];

  int? get currentPosition =>
      currentClassIndex == null ? null : currentClassIndex! + 1;

  List<ClassRankingEntry> get topThree => List.unmodifiable(entries.take(3));
}

enum RankingFailureKind { network, sessionInvalid, malformedData, unknown }

class RankingFailure implements Exception {
  const RankingFailure(this.kind, this.message, [this.cause]);

  final RankingFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedRankingRepository {
  Future<ClassRanking> loadRanking({required String currentClassId});
}
