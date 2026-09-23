import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'class_journey_repository.dart';

typedef JourneyRpcInvoker = Future<Object?> Function(String functionName);

abstract interface class ClassJourneyDataSource {
  bool get hasSession;

  Future<List<Map<String, dynamic>>> fetchJourney();
}

class SupabaseClassJourneyDataSource implements ClassJourneyDataSource {
  SupabaseClassJourneyDataSource(this._client, {JourneyRpcInvoker? rpcInvoker})
    : _rpcInvoker = rpcInvoker ?? ((name) async => await _client.rpc(name));

  static const rpcName = 'get_class_journey_v1';

  final SupabaseClient _client;
  final JourneyRpcInvoker _rpcInvoker;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<List<Map<String, dynamic>>> fetchJourney() async {
    final payload = await _rpcInvoker(rpcName);
    if (payload is! List) {
      throw const JourneyFailure(
        JourneyFailureKind.malformedData,
        'A resposta da Jornada possui formato inválido.',
      );
    }
    return payload
        .map((row) {
          if (row is! Map) {
            throw const JourneyFailure(
              JourneyFailureKind.malformedData,
              'A resposta da Jornada contém um estágio inválido.',
            );
          }
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }
}

class RemoteClassJourneyRepository
    implements AuthenticatedClassJourneyRepository {
  const RemoteClassJourneyRepository(this._dataSource);

  final ClassJourneyDataSource _dataSource;

  @override
  Future<AuthenticatedClassJourney?> loadJourney() async {
    if (!_dataSource.hasSession) {
      throw const JourneyFailure(
        JourneyFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }

    try {
      final rows = await _dataSource.fetchJourney();
      if (rows.isEmpty) return null;
      return _parseJourney(rows);
    } on JourneyFailure catch (error, stackTrace) {
      _debugLogJourneyError(error, stackTrace);
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      _debugLogJourneyError(error, stackTrace);
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw JourneyFailure(
          JourneyFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw JourneyFailure(
          JourneyFailureKind.network,
          'Não foi possível carregar a Jornada. Verifique sua conexão.',
          error,
        );
      }
      throw JourneyFailure(
        JourneyFailureKind.unknown,
        'Não foi possível carregar a Jornada agora.',
        error,
      );
    } catch (error, stackTrace) {
      _debugLogJourneyError(error, stackTrace);
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw JourneyFailure(
          JourneyFailureKind.network,
          'Não foi possível carregar a Jornada. Verifique sua conexão.',
          error,
        );
      }
      throw JourneyFailure(
        JourneyFailureKind.unknown,
        'Não foi possível carregar a Jornada agora.',
        error,
      );
    }
  }
}

AuthenticatedClassJourney _parseJourney(List<Map<String, dynamic>> rows) {
  if (rows.length != 3) {
    throw const JourneyFailure(
      JourneyFailureKind.malformedData,
      'A Jornada remota não contém exatamente os três estágios V1.',
    );
  }

  final campaignId = _requiredString(rows.first, 'campaign_id');
  final startsAt = _requiredDateTime(rows.first, 'starts_at');
  final endsAt = _requiredDateTime(rows.first, 'ends_at');
  final totalUnits = _requiredInt(rows.first, 'total_units');
  final validDepositCount = _requiredInt(rows.first, 'valid_deposit_count');
  final studentCount = _requiredInt(
    rows.first,
    'student_mission_completion_count',
  );
  final classCount = _requiredInt(rows.first, 'class_mission_completion_count');
  if (!startsAt.isBefore(endsAt)) {
    throw const JourneyFailure(
      JourneyFailureKind.malformedData,
      'A Jornada remota possui período inválido.',
    );
  }

  const expectedCodes = [
    JourneyStageCode.centralSquare,
    JourneyStageCode.springPark,
    JourneyStageCode.creativeSchool,
  ];
  const expectedTargets = [20, 25, 30];
  final stages = <AuthenticatedJourneyStage>[];
  var priorTargets = 0;
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (_requiredString(row, 'campaign_id') != campaignId ||
        _requiredDateTime(row, 'starts_at') != startsAt ||
        _requiredDateTime(row, 'ends_at') != endsAt ||
        _requiredInt(row, 'total_units') != totalUnits ||
        _requiredInt(row, 'valid_deposit_count') != validDepositCount ||
        _requiredInt(row, 'student_mission_completion_count') != studentCount ||
        _requiredInt(row, 'class_mission_completion_count') != classCount) {
      throw const JourneyFailure(
        JourneyFailureKind.malformedData,
        'Os estágios da Jornada não compartilham o mesmo snapshot.',
      );
    }

    final code = _parseStageCode(_requiredString(row, 'stage_code'));
    final order = _requiredInt(row, 'stage_order', positive: true);
    final target = _requiredInt(row, 'target_units', positive: true);
    final progress = _requiredInt(row, 'progress_units');
    final ratio = _requiredRatio(row, 'progress_ratio');
    final state = _parseStageState(_requiredString(row, 'state'));
    final remaining = _requiredInt(row, 'remaining_units');
    final expectedProgress = (totalUnits - priorTargets).clamp(0, target);
    final expectedState = progress >= target
        ? JourneyStageState.completed
        : totalUnits >= priorTargets
        ? JourneyStageState.active
        : JourneyStageState.locked;
    final expectedRatio = expectedProgress / target;

    if (code != expectedCodes[index] ||
        order != index + 1 ||
        target != expectedTargets[index] ||
        progress != expectedProgress ||
        state != expectedState ||
        remaining != target - progress ||
        (ratio - expectedRatio).abs() > 0.000001) {
      throw const JourneyFailure(
        JourneyFailureKind.malformedData,
        'A Jornada remota possui progresso ou sequência inconsistente.',
      );
    }

    stages.add(
      AuthenticatedJourneyStage(
        code: code,
        order: order,
        targetUnits: target,
        progressUnits: progress,
        progressRatio: ratio,
        state: state,
        remainingUnits: remaining,
      ),
    );
    priorTargets += target;
  }

  return AuthenticatedClassJourney(
    campaignId: campaignId,
    startsAt: startsAt,
    endsAt: endsAt,
    totalUnits: totalUnits,
    validDepositCount: validDepositCount,
    studentMissionCompletionCount: studentCount,
    classMissionCompletionCount: classCount,
    stages: List.unmodifiable(stages),
  );
}

JourneyStageCode _parseStageCode(String value) => switch (value) {
  'CENTRAL_SQUARE' => JourneyStageCode.centralSquare,
  'SPRING_PARK' => JourneyStageCode.springPark,
  'CREATIVE_SCHOOL' => JourneyStageCode.creativeSchool,
  _ => throw const JourneyFailure(
    JourneyFailureKind.malformedData,
    'A Jornada remota possui código de estágio inválido.',
  ),
};

JourneyStageState _parseStageState(String value) => switch (value) {
  'ACTIVE' => JourneyStageState.active,
  'LOCKED' => JourneyStageState.locked,
  'COMPLETED' => JourneyStageState.completed,
  _ => throw const JourneyFailure(
    JourneyFailureKind.malformedData,
    'A Jornada remota possui estado de estágio inválido.',
  ),
};

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw JourneyFailure(
    JourneyFailureKind.malformedData,
    'A Jornada remota não contém o campo obrigatório $key.',
  );
}

int _requiredInt(
  Map<String, dynamic> row,
  String key, {
  bool positive = false,
}) {
  final value = row[key];
  final parsed = switch (value) {
    int integer => integer,
    num number when number == number.roundToDouble() => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
  if (parsed == null || parsed < (positive ? 1 : 0)) {
    throw JourneyFailure(
      JourneyFailureKind.malformedData,
      'A Jornada remota não contém o campo numérico válido $key.',
    );
  }
  return parsed;
}

double _requiredRatio(Map<String, dynamic> row, String key) {
  final value = row[key];
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 1) {
    throw JourneyFailure(
      JourneyFailureKind.malformedData,
      'A Jornada remota não contém o percentual válido $key.',
    );
  }
  return parsed;
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw JourneyFailure(
    JourneyFailureKind.malformedData,
    'A Jornada remota não contém uma data válida em $key.',
  );
}

void _debugLogJourneyError(Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  if (error is PostgrestException) {
    debugPrint(
      '[journey] PostgREST failure: code=${error.code}, '
      'message=${error.message}, details=${error.details}, hint=${error.hint}',
    );
  } else {
    debugPrint('[journey] ${error.runtimeType}: $error');
  }
  debugPrintStack(
    label: '[journey] original stack trace',
    stackTrace: stackTrace,
  );
}

bool _looksLikeNetworkFailure(String message) {
  return message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('failed host') ||
      message.contains('clientexception') ||
      message.contains('timeout');
}
