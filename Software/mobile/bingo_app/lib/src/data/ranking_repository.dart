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

  ClassRankingEntry? get leader => entries.isEmpty ? null : entries.first;

  int? get xpToFirstPlace {
    final leaderXp = leader?.pointsClassBalance;
    final currentXp = currentClass?.pointsClassBalance;
    if (leaderXp == null || currentXp == null) return null;
    final remaining = leaderXp - currentXp;
    return remaining < 0 ? 0 : remaining;
  }

  double? get progressToFirstPlace {
    final leaderXp = leader?.pointsClassBalance;
    final currentXp = currentClass?.pointsClassBalance;
    final position = currentPosition;
    if (leaderXp == null || currentXp == null || position == null) return null;
    if (position == 1) return 1;
    if (leaderXp == 0) return 0;
    if (currentXp == leaderXp) return 1;
    return (currentXp / leaderXp).clamp(0.0, 1.0);
  }

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
