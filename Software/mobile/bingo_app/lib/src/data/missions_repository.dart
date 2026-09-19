enum AuthenticatedMissionScope { student, classGroup }

enum AuthenticatedMissionMetric { validDepositCount, classXpEarned }

class AuthenticatedMission {
  const AuthenticatedMission({
    required this.cycleId,
    required this.definitionId,
    required this.definitionCode,
    required this.definitionTitle,
    required this.scope,
    required this.metric,
    required this.startsAt,
    required this.endsAt,
    required this.target,
    required this.rewardBinCoins,
    required this.rewardXp,
    required this.progress,
    required this.isAchieved,
    required this.achievedAt,
    required this.isCompleted,
    required this.materializedAt,
  });

  final String cycleId;
  final String definitionId;
  final String definitionCode;
  final String definitionTitle;
  final AuthenticatedMissionScope scope;
  final AuthenticatedMissionMetric metric;
  final DateTime startsAt;
  final DateTime endsAt;
  final int target;
  final int rewardBinCoins;
  final int rewardXp;
  final int progress;
  final bool isAchieved;
  final DateTime? achievedAt;
  final bool isCompleted;
  final DateTime? materializedAt;
}

enum MissionsFailureKind { network, sessionInvalid, malformedData, unknown }

class MissionsFailure implements Exception {
  const MissionsFailure(this.kind, this.message, [this.cause]);

  final MissionsFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedMissionsRepository {
  Future<List<AuthenticatedMission>> loadActiveMissions();
}
