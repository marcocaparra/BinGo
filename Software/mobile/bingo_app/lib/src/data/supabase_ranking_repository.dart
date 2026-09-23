import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ranking_repository.dart';

typedef RankingRpcInvoker = Future<Object?> Function(String functionName);

abstract interface class RankingDataSource {
  bool get hasSession;

  Future<List<Map<String, dynamic>>> fetchRanking();
}

class SupabaseRankingDataSource implements RankingDataSource {
  SupabaseRankingDataSource(this._client, {RankingRpcInvoker? rpcInvoker})
    : _rpcInvoker = rpcInvoker ?? ((name) async => await _client.rpc(name));

  static const rpcName = 'get_class_ranking_v1';

  final SupabaseClient _client;
  final RankingRpcInvoker _rpcInvoker;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<List<Map<String, dynamic>>> fetchRanking() async {
    final payload = await _rpcInvoker(rpcName);
    if (payload is! List) {
      throw const RankingFailure(
        RankingFailureKind.malformedData,
        'A resposta do Ranking possui formato inválido.',
      );
    }

    return payload
        .map((row) {
          if (row is! Map) {
            throw const RankingFailure(
              RankingFailureKind.malformedData,
              'A resposta do Ranking contém um item inválido.',
            );
          }
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }
}

class RemoteRankingRepository implements AuthenticatedRankingRepository {
  const RemoteRankingRepository(this._dataSource);

  final RankingDataSource _dataSource;

  @override
  Future<ClassRanking> loadRanking({required String currentClassId}) async {
    if (!_dataSource.hasSession) {
      throw const RankingFailure(
        RankingFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }

    try {
      final rows = await _dataSource.fetchRanking();
      final entries = List<ClassRankingEntry>.unmodifiable(
        rows.map(_parseRankingEntry),
      );
      _validateOrderedEntries(entries);

      if (entries.isEmpty) {
        return const ClassRanking(entries: [], currentClassIndex: null);
      }

      final currentClassIndex = entries.indexWhere(
        (entry) => entry.classId == currentClassId,
      );
      if (currentClassIndex < 0) {
        throw const RankingFailure(
          RankingFailureKind.malformedData,
          'A turma do aluno não está presente no Ranking da escola.',
        );
      }

      return ClassRanking(
        entries: entries,
        currentClassIndex: currentClassIndex,
      );
    } on RankingFailure catch (error, stackTrace) {
      _debugLogRankingError(error, stackTrace);
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      _debugLogRankingError(error, stackTrace);
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw RankingFailure(
          RankingFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw RankingFailure(
          RankingFailureKind.network,
          'Não foi possível carregar o Ranking. Verifique sua conexão.',
          error,
        );
      }
      throw RankingFailure(
        RankingFailureKind.unknown,
        'Não foi possível carregar o Ranking agora.',
        error,
      );
    } catch (error, stackTrace) {
      _debugLogRankingError(error, stackTrace);
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw RankingFailure(
          RankingFailureKind.network,
          'Não foi possível carregar o Ranking. Verifique sua conexão.',
          error,
        );
      }
      throw RankingFailure(
        RankingFailureKind.unknown,
        'Não foi possível carregar o Ranking agora.',
        error,
      );
    }
  }
}

ClassRankingEntry _parseRankingEntry(Map<String, dynamic> row) {
  return ClassRankingEntry(
    classId: _requiredString(row, 'class_id'),
    className: _requiredString(row, 'class_name'),
    pointsClassBalance: _requiredBalance(row, 'points_class_balance'),
  );
}

void _validateOrderedEntries(List<ClassRankingEntry> entries) {
  final ids = <String>{};
  for (var index = 0; index < entries.length; index++) {
    final current = entries[index];
    if (!ids.add(current.classId)) {
      throw const RankingFailure(
        RankingFailureKind.malformedData,
        'A resposta do Ranking contém uma turma duplicada.',
      );
    }
    if (index == 0) continue;

    final previous = entries[index - 1];
    final balanceIsDescending =
        previous.pointsClassBalance >= current.pointsClassBalance;
    final tieIsDeterministic =
        previous.pointsClassBalance != current.pointsClassBalance ||
        previous.classId.compareTo(current.classId) < 0;
    if (!balanceIsDescending || !tieIsDeterministic) {
      throw const RankingFailure(
        RankingFailureKind.malformedData,
        'A resposta do Ranking não está na ordenação esperada.',
      );
    }
  }
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw RankingFailure(
      RankingFailureKind.malformedData,
      'O Ranking remoto não contém o campo obrigatório $key.',
    );
  }
  return value;
}

int _requiredBalance(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! int || value < 0) {
    throw RankingFailure(
      RankingFailureKind.malformedData,
      'O Ranking remoto não contém o saldo válido $key.',
    );
  }
  return value;
}

void _debugLogRankingError(Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  if (error is PostgrestException) {
    debugPrint(
      '[ranking] PostgREST failure: code=${error.code}, '
      'message=${error.message}, details=${error.details}, hint=${error.hint}',
    );
  } else {
    debugPrint('[ranking] ${error.runtimeType}: $error');
  }
  debugPrintStack(
    label: '[ranking] original stack trace',
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
