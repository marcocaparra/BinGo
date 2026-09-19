import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'missions_repository.dart';

typedef MissionsRpcInvoker = Future<Object?> Function(String functionName);

abstract interface class MissionsDataSource {
  bool get hasSession;

  Future<List<Map<String, dynamic>>> fetchActiveMissions();
}

class SupabaseMissionsDataSource implements MissionsDataSource {
  SupabaseMissionsDataSource(this._client, {MissionsRpcInvoker? rpcInvoker})
    : _rpcInvoker = rpcInvoker ?? ((name) async => await _client.rpc(name));

  static const rpcName = 'get_active_missions_v1';

  final SupabaseClient _client;
  final MissionsRpcInvoker _rpcInvoker;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<List<Map<String, dynamic>>> fetchActiveMissions() async {
    final payload = await _rpcInvoker(rpcName);
    if (payload is! List) {
      throw const MissionsFailure(
        MissionsFailureKind.malformedData,
        'A resposta de Missões possui formato inválido.',
      );
    }

    return payload
        .map((row) {
          if (row is! Map) {
            throw const MissionsFailure(
              MissionsFailureKind.malformedData,
              'A resposta de Missões contém um item inválido.',
            );
          }
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }
}

class RemoteMissionsRepository implements AuthenticatedMissionsRepository {
  const RemoteMissionsRepository(this._dataSource);

  final MissionsDataSource _dataSource;

  @override
  Future<List<AuthenticatedMission>> loadActiveMissions() async {
    if (!_dataSource.hasSession) {
      throw const MissionsFailure(
        MissionsFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }

    try {
      final rows = await _dataSource.fetchActiveMissions();
      return List.unmodifiable(rows.map(_parseMission));
    } on MissionsFailure catch (error, stackTrace) {
      _debugLogMissionsError(error, stackTrace);
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      _debugLogMissionsError(error, stackTrace);
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw MissionsFailure(
          MissionsFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw MissionsFailure(
          MissionsFailureKind.network,
          'Não foi possível carregar as missões. Verifique sua conexão.',
          error,
        );
      }
      throw MissionsFailure(
        MissionsFailureKind.unknown,
        'Não foi possível carregar as missões agora.',
        error,
      );
    } catch (error, stackTrace) {
      _debugLogMissionsError(error, stackTrace);
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw MissionsFailure(
          MissionsFailureKind.network,
          'Não foi possível carregar as missões. Verifique sua conexão.',
          error,
        );
      }
      throw MissionsFailure(
        MissionsFailureKind.unknown,
        'Não foi possível carregar as missões agora.',
        error,
      );
    }
  }
}

AuthenticatedMission _parseMission(Map<String, dynamic> row) {
  final scope = switch (_requiredString(row, 'scope')) {
    'STUDENT' => AuthenticatedMissionScope.student,
    'CLASS' => AuthenticatedMissionScope.classGroup,
    _ => throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota possui escopo inválido.',
    ),
  };
  final metric = switch (_requiredString(row, 'metric')) {
    'VALID_DEPOSIT_COUNT' => AuthenticatedMissionMetric.validDepositCount,
    'CLASS_XP_EARNED' => AuthenticatedMissionMetric.classXpEarned,
    _ => throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota possui métrica inválida.',
    ),
  };
  if ((scope == AuthenticatedMissionScope.student &&
          metric != AuthenticatedMissionMetric.validDepositCount) ||
      (scope == AuthenticatedMissionScope.classGroup &&
          metric != AuthenticatedMissionMetric.classXpEarned)) {
    throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota possui uma combinação inválida de escopo e métrica.',
    );
  }

  final startsAt = _requiredDateTime(row, 'starts_at');
  final endsAt = _requiredDateTime(row, 'ends_at');
  if (!startsAt.isBefore(endsAt)) {
    throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota possui um período inválido.',
    );
  }

  final target = _requiredInt(row, 'target', positive: true);
  final rewardBinCoins = _requiredInt(row, 'reward_bincoins');
  final rewardXp = _requiredInt(row, 'reward_xp');
  if (rewardBinCoins == 0 && rewardXp == 0) {
    throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota não possui recompensa válida.',
    );
  }
  final progress = _requiredInt(row, 'progress');
  final isAchieved = _requiredBool(row, 'is_achieved');
  final achievedAt = _optionalDateTime(row, 'achieved_at');
  final isCompleted = _requiredBool(row, 'is_completed');
  final materializedAt = _optionalDateTime(row, 'materialized_at');
  if (isAchieved != (achievedAt != null) ||
      isCompleted != (materializedAt != null) ||
      (isCompleted && !isAchieved)) {
    throw const MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota possui estado temporal inconsistente.',
    );
  }

  return AuthenticatedMission(
    cycleId: _requiredString(row, 'cycle_id'),
    definitionId: _requiredString(row, 'definition_id'),
    definitionCode: _requiredString(row, 'definition_code'),
    definitionTitle: _requiredString(row, 'definition_title'),
    scope: scope,
    metric: metric,
    startsAt: startsAt,
    endsAt: endsAt,
    target: target,
    rewardBinCoins: rewardBinCoins,
    rewardXp: rewardXp,
    progress: progress,
    isAchieved: isAchieved,
    achievedAt: achievedAt,
    isCompleted: isCompleted,
    materializedAt: materializedAt,
  );
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota não contém o campo obrigatório $key.',
    );
  }
  return value;
}

int _requiredInt(
  Map<String, dynamic> row,
  String key, {
  bool positive = false,
}) {
  final value = row[key];
  if (value is! int || value < (positive ? 1 : 0)) {
    throw MissionsFailure(
      MissionsFailureKind.malformedData,
      'A missão remota não contém o campo numérico válido $key.',
    );
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is bool) return value;
  throw MissionsFailure(
    MissionsFailureKind.malformedData,
    'A missão remota não contém o campo booleano obrigatório $key.',
  );
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final value = _optionalDateTime(row, key);
  if (value != null) return value;
  throw MissionsFailure(
    MissionsFailureKind.malformedData,
    'A missão remota não contém uma data válida em $key.',
  );
}

DateTime? _optionalDateTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw MissionsFailure(
    MissionsFailureKind.malformedData,
    'A missão remota contém uma data inválida em $key.',
  );
}

void _debugLogMissionsError(Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  if (error is PostgrestException) {
    debugPrint(
      '[missions] PostgREST failure: code=${error.code}, '
      'message=${error.message}, details=${error.details}, hint=${error.hint}',
    );
  } else {
    debugPrint('[missions] ${error.runtimeType}: $error');
  }
  debugPrintStack(
    label: '[missions] original stack trace',
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
