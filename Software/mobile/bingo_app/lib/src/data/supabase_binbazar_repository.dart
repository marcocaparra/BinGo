import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'binbazar_repository.dart';

typedef BinBazarRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

abstract interface class BinBazarDataSource {
  bool get hasSession;

  Future<List<Map<String, dynamic>>> invoke(
    String functionName, [
    Map<String, dynamic> parameters,
  ]);
}

class SupabaseBinBazarDataSource implements BinBazarDataSource {
  SupabaseBinBazarDataSource(this._client, {BinBazarRpcInvoker? rpcInvoker})
    : _rpcInvoker =
          rpcInvoker ??
          ((name, parameters) async =>
              await _client.rpc(name, params: parameters));

  final SupabaseClient _client;
  final BinBazarRpcInvoker _rpcInvoker;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<List<Map<String, dynamic>>> invoke(
    String functionName, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    final payload = await _rpcInvoker(functionName, parameters);
    if (payload is! List) {
      throw const BinBazarFailure(
        BinBazarFailureKind.malformedData,
        'O servidor retornou dados do BinBazar em formato inválido.',
      );
    }
    return payload
        .map((row) {
          if (row is! Map) {
            throw const BinBazarFailure(
              BinBazarFailureKind.malformedData,
              'O servidor retornou um item inválido do BinBazar.',
            );
          }
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }
}

class RemoteBinBazarRepository implements AuthenticatedBinBazarRepository {
  const RemoteBinBazarRepository(this._dataSource);

  static const catalogRpc = 'get_my_binbazar_catalog_v1';
  static const redemptionsRpc = 'get_my_redemptions_v1';
  static const statementRpc = 'get_my_bincoin_statement_v1';
  static const requestRpc = 'request_redemption_v1';
  static const cancelRpc = 'cancel_my_redemption_v1';

  final BinBazarDataSource _dataSource;

  @override
  Future<List<BinBazarReward>> loadCatalog() => _guard(() async {
    final rows = await _dataSource.invoke(catalogRpc);
    return List.unmodifiable(rows.map(_parseReward));
  });

  @override
  Future<List<BinBazarRedemption>> loadRedemptions() => _guard(() async {
    final rows = await _dataSource.invoke(redemptionsRpc);
    return List.unmodifiable(rows.map(_parseRedemption));
  });

  @override
  Future<List<BinCoinStatementMovement>> loadStatement() => _guard(() async {
    final rows = await _dataSource.invoke(statementRpc);
    return List.unmodifiable(rows.map(_parseMovement));
  });

  @override
  Future<RedemptionMutation> requestRedemption({
    required String clientRequestId,
    required String rewardId,
  }) => _guard(() async {
    if (clientRequestId.trim().isEmpty || rewardId.trim().isEmpty) {
      throw const BinBazarFailure(
        BinBazarFailureKind.malformedData,
        'A intenção de resgate não possui identificadores válidos.',
      );
    }
    final rows = await _dataSource.invoke(requestRpc, {
      'p_request_id': clientRequestId,
      'p_reward_id': rewardId,
    });
    return _parseMutation(rows);
  });

  @override
  Future<RedemptionMutation> cancelRedemption({required String redemptionId}) =>
      _guard(() async {
        if (redemptionId.trim().isEmpty) {
          throw const BinBazarFailure(
            BinBazarFailureKind.malformedData,
            'O resgate não possui identificador válido.',
          );
        }
        final rows = await _dataSource.invoke(cancelRpc, {
          'p_redemption_id': redemptionId,
        });
        return _parseMutation(rows);
      });

  Future<T> _guard<T>(Future<T> Function() operation) async {
    if (!_dataSource.hasSession) {
      throw const BinBazarFailure(
        BinBazarFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    try {
      return await operation();
    } on BinBazarFailure {
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      _debugLog(error, stackTrace);
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw BinBazarFailure(
          BinBazarFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (error.code == '23505') {
        throw BinBazarFailure(
          BinBazarFailureKind.conflict,
          'Esta intenção de resgate já foi usada para outro pedido.',
          error,
        );
      }
      if (error.code == '23514' || error.code == '55000') {
        throw BinBazarFailure(
          BinBazarFailureKind.rejected,
          error.message,
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw BinBazarFailure(
          BinBazarFailureKind.network,
          'Não foi possível atualizar o BinBazar. Verifique sua conexão.',
          error,
        );
      }
      throw BinBazarFailure(
        BinBazarFailureKind.unknown,
        'Não foi possível atualizar o BinBazar agora.',
        error,
      );
    } catch (error, stackTrace) {
      _debugLog(error, stackTrace);
      if (error is BinBazarFailure) rethrow;
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw BinBazarFailure(
          BinBazarFailureKind.network,
          'Não foi possível atualizar o BinBazar. Verifique sua conexão.',
          error,
        );
      }
      throw BinBazarFailure(
        BinBazarFailureKind.unknown,
        'Não foi possível atualizar o BinBazar agora.',
        error,
      );
    }
  }
}

RedemptionMutation _parseMutation(List<Map<String, dynamic>> rows) {
  if (rows.length != 1) {
    throw const BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'A operação de resgate deve retornar exatamente um resultado.',
    );
  }
  final row = rows.single;
  return RedemptionMutation(
    redemption: _parseRedemption(row),
    pointsStudentBalance: _requiredNonNegativeInt(
      row,
      'points_student_balance',
    ),
    replayed: _requiredBool(row, 'replayed'),
  );
}

BinBazarReward _parseReward(Map<String, dynamic> row) {
  final stock = row['stock_qty'];
  if (stock != null && (stock is! int || stock < 0)) {
    throw const BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'O catálogo contém estoque inválido.',
    );
  }
  return BinBazarReward(
    id: _requiredString(row, 'reward_id'),
    name: _requiredString(row, 'name'),
    description: _optionalString(row, 'description'),
    costPoints: _requiredPositiveInt(row, 'cost_points'),
    isActive: _requiredBool(row, 'is_active'),
    stockQty: stock as int?,
  );
}

BinBazarRedemption _parseRedemption(Map<String, dynamic> row) {
  final status = _requiredString(row, 'status');
  if (!const {'PENDING', 'DELIVERED', 'CANCELED', 'EXPIRED'}.contains(status)) {
    throw const BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'O histórico contém estado de resgate inválido.',
    );
  }
  return BinBazarRedemption(
    id: _requiredString(row, 'redemption_id'),
    rewardId: _requiredString(row, 'reward_id'),
    rewardName: _requiredString(row, 'reward_name'),
    costPoints: _requiredPositiveInt(row, 'cost_points'),
    code: _requiredString(row, 'code'),
    status: status,
    requestChannel: row['request_channel']?.toString() ?? 'MOBILE',
    createdAt: _requiredDateTime(row, 'created_at'),
    deliveredAt: _optionalDateTime(row, 'delivered_at'),
    canceledAt: _optionalDateTime(row, 'canceled_at'),
  );
}

BinCoinStatementMovement _parseMovement(Map<String, dynamic> row) {
  final amount = _requiredInt(row, 'amount');
  if (amount == 0) {
    throw const BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'O Extrato contém um movimento de valor zero.',
    );
  }
  return BinCoinStatementMovement(
    id: _requiredString(row, 'movement_id'),
    occurredAt: _requiredDateTime(row, 'occurred_at'),
    type: _requiredString(row, 'movement_type'),
    amount: amount,
    title: _requiredString(row, 'title'),
    redemptionId: _optionalString(row, 'redemption_id'),
    sourceId: _requiredString(row, 'source_id'),
  );
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null || value.toString().trim().isEmpty) {
    throw BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'O servidor não retornou o campo obrigatório $key.',
    );
  }
  return value.toString();
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value.toString().trim().isEmpty) {
    throw BinBazarFailure(
      BinBazarFailureKind.malformedData,
      'O servidor retornou um valor inválido para $key.',
    );
  }
  return value.toString();
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw BinBazarFailure(
    BinBazarFailureKind.malformedData,
    'O servidor não retornou o campo inteiro $key.',
  );
}

int _requiredPositiveInt(Map<String, dynamic> row, String key) {
  final value = _requiredInt(row, key);
  if (value > 0) return value;
  throw BinBazarFailure(
    BinBazarFailureKind.malformedData,
    'O servidor retornou um valor inválido para $key.',
  );
}

int _requiredNonNegativeInt(Map<String, dynamic> row, String key) {
  final value = _requiredInt(row, key);
  if (value >= 0) return value;
  throw BinBazarFailure(
    BinBazarFailureKind.malformedData,
    'O servidor retornou um saldo inválido.',
  );
}

bool _requiredBool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is bool) return value;
  throw BinBazarFailure(
    BinBazarFailureKind.malformedData,
    'O servidor não retornou o campo booleano $key.',
  );
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final parsed = _optionalDateTime(row, key);
  if (parsed != null) return parsed;
  throw BinBazarFailure(
    BinBazarFailureKind.malformedData,
    'O servidor não retornou uma data válida em $key.',
  );
}

DateTime? _optionalDateTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool _looksLikeNetworkFailure(String message) {
  return message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('failed host') ||
      message.contains('clientexception') ||
      message.contains('timeout');
}

void _debugLog(Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  debugPrint('[binbazar] ${error.runtimeType}: $error');
  debugPrintStack(
    label: '[binbazar] original stack trace',
    stackTrace: stackTrace,
  );
}
