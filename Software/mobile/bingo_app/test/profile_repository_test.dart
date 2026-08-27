import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/supabase_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements ProfileDataSource {
  _FakeDataSource({
    this.hasSession = true,
    this.currentUserId = 'auth-user-id',
    this.student,
    this.classroom,
    this.school,
  });

  @override
  final bool hasSession;
  @override
  final String? currentUserId;
  final Map<String, dynamic>? student;
  final Map<String, dynamic>? classroom;
  final Map<String, dynamic>? school;

  String? requestedAuthUserId;

  @override
  Future<Map<String, dynamic>?> fetchOwnStudent(String authUserId) async {
    requestedAuthUserId = authUserId;
    return student;
  }

  @override
  Future<Map<String, dynamic>?> fetchClass(String classId) async => classroom;

  @override
  Future<Map<String, dynamic>?> fetchSchool(String schoolId) async => school;
}

void main() {
  const student = <String, dynamic>{
    'id': 'student-id',
    'name': 'Aluno Remoto',
    'school_id': 'school-id',
    'class_id': 'class-id',
    'points_student_balance': 760,
    'status': 'ACTIVE',
  };
  const classroom = <String, dynamic>{
    'id': 'class-id',
    'school_id': 'school-id',
    'name': '9º Ano A',
    'points_class_balance': 1190,
  };
  const school = <String, dynamic>{'id': 'school-id', 'name': 'Escola Remota'};

  test('repository remoto mapeia somente campos reais do perfil', () async {
    final dataSource = _FakeDataSource(
      student: student,
      classroom: classroom,
      school: school,
    );
    final repository = RemoteProfileRepository(dataSource);

    final profile = await repository.loadProfile();

    expect(profile.name, 'Aluno Remoto');
    expect(profile.binCoinsBalance, 760);
    expect(profile.classXpBalance, 1190);
    expect(profile.schoolName, 'Escola Remota');
    expect(profile.className, '9º Ano A');
    expect(dataSource.requestedAuthUserId, 'auth-user-id');
  });

  test('sessão ausente falha sem consultar ou retornar mock', () async {
    final repository = RemoteProfileRepository(
      _FakeDataSource(hasSession: false),
    );

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.sessionInvalid,
        ),
      ),
    );
  });

  test('usuário corrente ausente é tratado como sessão inválida', () async {
    final repository = RemoteProfileRepository(
      _FakeDataSource(currentUserId: null),
    );

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.sessionInvalid,
        ),
      ),
    );
  });

  test('aluno não vinculado recebe erro específico', () async {
    final repository = RemoteProfileRepository(_FakeDataSource());

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.authLinkMissing,
        ),
      ),
    );
  });

  test('turma fora da escola vinculada é rejeitada', () async {
    final repository = RemoteProfileRepository(
      _FakeDataSource(
        student: student,
        classroom: {...classroom, 'school_id': 'another-school'},
        school: school,
      ),
    );

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.notFound,
        ),
      ),
    );
  });

  test('escola vinculada ausente é rejeitada', () async {
    final repository = RemoteProfileRepository(
      _FakeDataSource(student: student, classroom: classroom),
    );

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.notFound,
        ),
      ),
    );
  });

  test('saldo remoto malformado é rejeitado sem valor fictício', () async {
    final repository = RemoteProfileRepository(
      _FakeDataSource(
        student: {...student, 'points_student_balance': null},
        classroom: classroom,
        school: school,
      ),
    );

    await expectLater(
      repository.loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.malformedData,
        ),
      ),
    );
  });
}
