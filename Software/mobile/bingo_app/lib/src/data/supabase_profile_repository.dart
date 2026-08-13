import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_repository.dart';

abstract interface class ProfileDataSource {
  bool get hasSession;

  Future<Map<String, dynamic>?> fetchOwnStudent();

  Future<Map<String, dynamic>?> fetchClass(String classId);

  Future<Map<String, dynamic>?> fetchSchool(String schoolId);
}

class SupabaseProfileDataSource implements ProfileDataSource {
  const SupabaseProfileDataSource(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  @override
  Future<Map<String, dynamic>?> fetchOwnStudent() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('students')
        .select('id, name, school_id, class_id, points_student_balance, status')
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
}

class RemoteProfileRepository implements ProfileRepository {
  const RemoteProfileRepository(this._dataSource);

  final ProfileDataSource _dataSource;

  @override
  Future<StudentProfile> loadProfile() async {
    if (!_dataSource.hasSession) {
      throw const ProfileFailure(
        ProfileFailureKind.sessionInvalid,
        'Sua sessão expirou. Entre novamente.',
      );
    }

    try {
      final student = await _dataSource.fetchOwnStudent();
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

      return StudentProfile(
        id: id,
        name: name,
        schoolId: schoolId,
        schoolName: _requiredString(school, 'name'),
        classId: classId,
        className: _requiredString(classroom, 'name'),
        pointsStudentBalance: pointsStudentBalance,
        pointsClassBalance: _requiredInt(classroom, 'points_class_balance'),
        status: status,
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

bool _looksLikeNetworkFailure(String message) {
  return message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('failed host') ||
      message.contains('clientexception') ||
      message.contains('timeout');
}
