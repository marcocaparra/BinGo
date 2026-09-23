enum JourneyStageCode { centralSquare, springPark, creativeSchool }

enum JourneyStageState { active, locked, completed }

class AuthenticatedJourneyStage {
  const AuthenticatedJourneyStage({
    required this.code,
    required this.order,
    required this.targetUnits,
    required this.progressUnits,
    required this.progressRatio,
    required this.state,
    required this.remainingUnits,
  });

  final JourneyStageCode code;
  final int order;
  final int targetUnits;
  final int progressUnits;
  final double progressRatio;
  final JourneyStageState state;
  final int remainingUnits;

  String get scenarioId => switch (code) {
    JourneyStageCode.centralSquare => 'central-square',
    JourneyStageCode.springPark => 'spring-park',
    JourneyStageCode.creativeSchool => 'creative-school',
  };
}

class AuthenticatedClassJourney {
  const AuthenticatedClassJourney({
    required this.campaignId,
    required this.startsAt,
    required this.endsAt,
    required this.totalUnits,
    required this.validDepositCount,
    required this.studentMissionCompletionCount,
    required this.classMissionCompletionCount,
    required this.stages,
  });

  final String campaignId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int totalUnits;
  final int validDepositCount;
  final int studentMissionCompletionCount;
  final int classMissionCompletionCount;
  final List<AuthenticatedJourneyStage> stages;

  AuthenticatedJourneyStage get currentStage {
    for (final stage in stages) {
      if (stage.state == JourneyStageState.active) return stage;
    }
    return stages.last;
  }
}

enum JourneyFailureKind { network, sessionInvalid, malformedData, unknown }

class JourneyFailure implements Exception {
  const JourneyFailure(this.kind, this.message, [this.cause]);

  final JourneyFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedClassJourneyRepository {
  Future<AuthenticatedClassJourney?> loadJourney();
}
