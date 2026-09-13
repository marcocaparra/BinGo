import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'deposit_history_repository.dart';

abstract interface class DepositHistoryDataSource {
  bool get hasSession;

  Future<List<Map<String, dynamic>>> fetchValidDeposits({
    required String studentId,
    required int limit,
  });
}

class SupabaseDepositHistoryDataSource implements DepositHistoryDataSource {
  const SupabaseDepositHistoryDataSource(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<List<Map<String, dynamic>>> fetchValidDeposits({
    required String studentId,
    required int limit,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('deposits')
        .select(
          'id, student_id, created_at, is_valid, detected_type, '
          'waste_category_id, category_source, bonus_bincoins_awarded, '
          'points_awarded_student, points_awarded_class, '
          'waste_categories!deposits_waste_category_id_fkey('
          'id, code, display_name)',
        )
        .eq('student_id', studentId)
        .eq('is_valid', true)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }
}

class RemoteDepositHistoryRepository
    implements AuthenticatedDepositHistoryRepository {
  const RemoteDepositHistoryRepository(this._dataSource);

  static const initialLimit = 20;

  final DepositHistoryDataSource _dataSource;

  @override
  Future<List<AuthenticatedDepositHistoryEntry>> loadHistory({
    required String studentId,
  }) async {
    final normalizedStudentId = studentId.trim();
    if (!_dataSource.hasSession) {
      throw const DepositHistoryFailure(
        DepositHistoryFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    if (normalizedStudentId.isEmpty) {
      throw const DepositHistoryFailure(
        DepositHistoryFailureKind.malformedData,
        'O perfil autenticado não possui um identificador de aluno válido.',
      );
    }

    try {
      final rows = await _dataSource.fetchValidDeposits(
        studentId: normalizedStudentId,
        limit: initialLimit,
      );
      final entries =
          rows
              .map((row) => _parseEntry(row, normalizedStudentId))
              .where((entry) => entry.isValid)
              .toList()
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return List.unmodifiable(entries);
    } on DepositHistoryFailure catch (error, stackTrace) {
      _debugLogDepositHistoryError(error, stackTrace);
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      _debugLogDepositHistoryError(error, stackTrace);
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw DepositHistoryFailure(
          DepositHistoryFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw DepositHistoryFailure(
          DepositHistoryFailureKind.network,
          'Não foi possível carregar os descartes. Verifique sua conexão.',
          error,
        );
      }
      throw DepositHistoryFailure(
        DepositHistoryFailureKind.unknown,
        'Não foi possível carregar os descartes agora.',
        error,
      );
    } catch (error, stackTrace) {
      _debugLogDepositHistoryError(error, stackTrace);
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw DepositHistoryFailure(
          DepositHistoryFailureKind.network,
          'Não foi possível carregar os descartes. Verifique sua conexão.',
          error,
        );
      }
      throw DepositHistoryFailure(
        DepositHistoryFailureKind.unknown,
        'Não foi possível carregar os descartes agora.',
        error,
      );
    }
  }
}

void _debugLogDepositHistoryError(Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  if (error is PostgrestException) {
    debugPrint(
      '[deposit_history] PostgREST failure: '
      'code=${error.code}, message=${error.message}, '
      'details=${error.details}, hint=${error.hint}',
    );
  } else {
    debugPrint('[deposit_history] ${error.runtimeType}: $error');
  }
  debugPrintStack(
    label: '[deposit_history] original stack trace',
    stackTrace: stackTrace,
  );
}

AuthenticatedDepositHistoryEntry _parseEntry(
  Map<String, dynamic> row,
  String expectedStudentId,
) {
  final studentId = _requiredString(row, 'student_id');
  if (studentId != expectedStudentId) {
    throw const DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'O histórico remoto retornou um descarte de outro aluno.',
    );
  }

  final isValid = _requiredBool(row, 'is_valid');
  final detectedType = _optionalString(row, 'detected_type');
  final category = _parseCategory(row);
  if (isValid && category == null && detectedType == null) {
    throw const DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'O descarte validado não possui categoria nem tipo detectado.',
    );
  }

  return AuthenticatedDepositHistoryEntry(
    id: _requiredString(row, 'id'),
    createdAt: _requiredDateTime(row, 'created_at'),
    isValid: isValid,
    detectedType: detectedType,
    category: category,
    categorySource: _optionalString(row, 'category_source'),
    bonusBinCoinsAwarded: _requiredNonNegativeInt(
      row,
      'bonus_bincoins_awarded',
    ),
    pointsAwardedStudent: _requiredNonNegativeInt(
      row,
      'points_awarded_student',
    ),
    pointsAwardedClass: _requiredNonNegativeInt(row, 'points_awarded_class'),
  );
}

DepositHistoryCategory? _parseCategory(Map<String, dynamic> row) {
  final relation = row['waste_categories'];
  if (relation == null) return null;
  if (relation is! Map) {
    throw const DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'A categoria do descarte possui formato inválido.',
    );
  }

  final category = Map<String, dynamic>.from(relation);
  final parsed = DepositHistoryCategory(
    id: _requiredString(category, 'id'),
    code: _requiredString(category, 'code'),
    displayName: _requiredString(category, 'display_name'),
  );
  final wasteCategoryId = _optionalString(row, 'waste_category_id');
  if (wasteCategoryId != null && wasteCategoryId != parsed.id) {
    throw const DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'A categoria relacionada não corresponde ao descarte.',
    );
  }
  return parsed;
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'O histórico remoto não contém o campo obrigatório $key.',
    );
  }
  return value;
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw DepositHistoryFailure(
      DepositHistoryFailureKind.malformedData,
      'O histórico remoto contém um valor inválido para $key.',
    );
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is bool) return value;
  throw DepositHistoryFailure(
    DepositHistoryFailureKind.malformedData,
    'O histórico remoto não contém o campo booleano obrigatório $key.',
  );
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw DepositHistoryFailure(
    DepositHistoryFailureKind.malformedData,
    'O histórico remoto não contém uma data válida em $key.',
  );
}

int _requiredNonNegativeInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int && value >= 0) return value;
  throw DepositHistoryFailure(
    DepositHistoryFailureKind.malformedData,
    'O histórico remoto não contém o campo numérico obrigatório $key.',
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
