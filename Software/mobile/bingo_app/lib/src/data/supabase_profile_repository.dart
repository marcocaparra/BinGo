import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_repository.dart';

typedef ProfileRpcInvoker = Future<Object?> Function(String functionName);

abstract interface class ProfileDataSource {
  bool get hasSession;

  String? get currentUserId;

  Future<Map<String, dynamic>?> fetchOwnStudent(String authUserId);

  Future<Map<String, dynamic>?> fetchClass(String classId);

  Future<Map<String, dynamic>?> fetchSchool(String schoolId);

  Future<List<Map<String, dynamic>>> fetchProgress();
}

class SupabaseProfileDataSource implements ProfileDataSource {
  SupabaseProfileDataSource(this._client, {ProfileRpcInvoker? rpcInvoker})
    : _rpcInvoker = rpcInvoker ?? ((name) async => await _client.rpc(name));

  static const progressRpcName = 'get_student_profile_progress_v1';

  final SupabaseClient _client;
  final ProfileRpcInvoker _rpcInvoker;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Map<String, dynamic>?> fetchOwnStudent(String authUserId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('students')
        .select('id, name, school_id, class_id, points_student_balance, status')
        .eq('auth_user_id', authUserId)
        .limit(2);
    if (rows.isEmpty) return null;
    if (rows.length > 1) {
      throw const ProfileFailure(
        ProfileFailureKind.malformedData,
        'Mais de um perfil foi associado à sessão autenticada.',
      );
    }
    return rows.single;
  }

  @override
  Future<Map<String, dynamic>?> fetchClass(String classId) {
    return _client
        .from('classes')
        .select('id, school_id, name, segment, grade, points_class_balance')
        .eq('id', classId)
        .maybeSingle();
  }

  @override
  Future<Map<String, dynamic>?> fetchSchool(String schoolId) {
    return _client
        .from('schools')
        .select('id, name')
        .eq('id', schoolId)
        .maybeSingle();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProgress() async {
    final payload = await _rpcInvoker(progressRpcName);
    if (payload is! List) {
      throw const ProfileFailure(
        ProfileFailureKind.malformedData,
        'A resposta da Trilha possui formato inválido.',
      );
    }

    return payload
        .map((row) {
          if (row is! Map) {
            throw const ProfileFailure(
              ProfileFailureKind.malformedData,
              'A resposta da Trilha contém um item inválido.',
            );
          }
          return Map<String, dynamic>.from(row);
        })
        .toList(growable: false);
  }
}

class RemoteProfileRepository implements AuthenticatedProfileRepository {
  const RemoteProfileRepository(this._dataSource);

  final ProfileDataSource _dataSource;

  @override
  Future<AuthenticatedStudentProfile> loadProfile() async {
    final authUserId = _dataSource.currentUserId;
    if (!_dataSource.hasSession || authUserId == null) {
      throw const ProfileFailure(
        ProfileFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }

    try {
      final student = await _dataSource.fetchOwnStudent(authUserId);
      if (student == null) {
        throw const ProfileFailure(
          ProfileFailureKind.authLinkMissing,
          'Esta conta ainda não está vinculada a um aluno BinGo.',
        );
      }

      final id = _requiredString(student, 'id');
      final name = _requiredString(student, 'name');
      final schoolId = _requiredString(student, 'school_id');
      final classId = _requiredString(student, 'class_id');
      final pointsStudentBalance = _requiredInt(
        student,
        'points_student_balance',
      );
      final status = _requiredString(student, 'status');

      final classroom = await _dataSource.fetchClass(classId);
      if (classroom == null || classroom['school_id']?.toString() != schoolId) {
        throw const ProfileFailure(
          ProfileFailureKind.notFound,
          'A turma associada ao perfil não foi encontrada.',
        );
      }

      final school = await _dataSource.fetchSchool(schoolId);
      if (school == null) {
        throw const ProfileFailure(
          ProfileFailureKind.notFound,
          'A escola associada ao perfil não foi encontrada.',
        );
      }

      final progressRows = await _dataSource.fetchProgress();
      if (progressRows.length != 1) {
        throw const ProfileFailure(
          ProfileFailureKind.malformedData,
          'A Trilha do perfil deve retornar exatamente um resultado.',
        );
      }
      final progress = _parseProgress(progressRows.single);
      if (progress.studentId != id) {
        throw const ProfileFailure(
          ProfileFailureKind.malformedData,
          'A Trilha retornada não pertence ao aluno autenticado.',
        );
      }

      return AuthenticatedStudentProfile(
        id: id,
        name: name,
        schoolId: schoolId,
        schoolName: _requiredString(school, 'name'),
        classId: classId,
        className: _requiredString(classroom, 'name'),
        pointsStudentBalance: pointsStudentBalance,
        pointsClassBalance: _requiredInt(classroom, 'points_class_balance'),
        status: status,
        progress: progress,
      );
    } on ProfileFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (normalized.contains('jwt') || normalized.contains('pgrst301')) {
        throw ProfileFailure(
          ProfileFailureKind.sessionInvalid,
          'Sua sessão expirou. Entre novamente.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw ProfileFailure(
          ProfileFailureKind.network,
          'Não foi possível carregar o perfil. Verifique sua conexão.',
          error,
        );
      }
      throw ProfileFailure(
        ProfileFailureKind.unknown,
        'Não foi possível carregar o perfil agora.',
        error,
      );
    } catch (error) {
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw ProfileFailure(
          ProfileFailureKind.network,
          'Não foi possível carregar o perfil. Verifique sua conexão.',
          error,
        );
      }
      throw ProfileFailure(
        ProfileFailureKind.unknown,
        'Não foi possível carregar o perfil agora.',
        error,
      );
    }
  }
}

AuthenticatedProfileProgress _parseProgress(Map<String, dynamic> row) {
  final studentId = _requiredString(row, 'student_id');
  final validDepositCount = _requiredProgressInt(row, 'valid_deposit_count');
  final levelNumber = _requiredProgressInt(row, 'level_number');
  final levelCode = _requiredString(row, 'level_code');
  final remainingToNextLevel = _requiredProgressInt(
    row,
    'remaining_to_next_level',
  );
  final progressToNextLevel = _requiredProgressNumber(
    row,
    'progress_to_next_level',
  );
  final expected = _expectedProgress(validDepositCount);

  if (levelNumber != expected.levelNumber ||
      levelCode != expected.levelCode ||
      remainingToNextLevel != expected.remainingToNextLevel ||
      (progressToNextLevel - expected.progressToNextLevel).abs() >
          0.000000001) {
    throw const ProfileFailure(
      ProfileFailureKind.malformedData,
      'A resposta da Trilha possui nível ou progresso inconsistente.',
    );
  }

  return AuthenticatedProfileProgress(
    studentId: studentId,
    validDepositCount: validDepositCount,
    levelNumber: levelNumber,
    levelCode: levelCode,
    remainingToNextLevel: remainingToNextLevel,
    progressToNextLevel: progressToNextLevel,
  );
}

({
  int levelNumber,
  String levelCode,
  int remainingToNextLevel,
  double progressToNextLevel,
})
_expectedProgress(int count) {
  if (count >= 50) {
    return (
      levelNumber: 5,
      levelCode: 'HERO',
      remainingToNextLevel: 0,
      progressToNextLevel: 1,
    );
  }
  if (count >= 20) {
    return (
      levelNumber: 4,
      levelCode: 'GUARDIAN',
      remainingToNextLevel: 50 - count,
      progressToNextLevel: count / 50,
    );
  }
  if (count >= 10) {
    return (
      levelNumber: 3,
      levelCode: 'RESTORER',
      remainingToNextLevel: 20 - count,
      progressToNextLevel: count / 20,
    );
  }
  if (count >= 5) {
    return (
      levelNumber: 2,
      levelCode: 'EXPLORER',
      remainingToNextLevel: 10 - count,
      progressToNextLevel: count / 10,
    );
  }
  if (count >= 1) {
    return (
      levelNumber: 1,
      levelCode: 'APPRENTICE',
      remainingToNextLevel: 5 - count,
      progressToNextLevel: count / 5,
    );
  }
  return (
    levelNumber: 0,
    levelCode: 'NONE',
    remainingToNextLevel: 1,
    progressToNextLevel: 0,
  );
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null || value.toString().trim().isEmpty) {
    throw ProfileFailure(
      ProfileFailureKind.malformedData,
      'O perfil remoto não contém o campo obrigatório $key.',
    );
  }
  return value.toString();
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw ProfileFailure(
    ProfileFailureKind.malformedData,
    'O perfil remoto não contém o campo numérico obrigatório $key.',
  );
}

int _requiredProgressInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int && value >= 0) return value;
  if (value is num &&
      value.isFinite &&
      value >= 0 &&
      value == value.roundToDouble()) {
    return value.toInt();
  }
  throw ProfileFailure(
    ProfileFailureKind.malformedData,
    'A Trilha remota não contém o campo inteiro válido $key.',
  );
}

double _requiredProgressNumber(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is num && value.isFinite && value >= 0 && value <= 1) {
    return value.toDouble();
  }
  throw ProfileFailure(
    ProfileFailureKind.malformedData,
    'A Trilha remota não contém o progresso válido $key.',
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
