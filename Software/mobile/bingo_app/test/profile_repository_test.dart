import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/supabase_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements ProfileDataSource {
  _FakeDataSource({
    this.hasSession = true,
    this.student,
    this.classroom,
    this.school,
  });

  @override
  final bool hasSession;
  final Map<String, dynamic>? student;
  final Map<String, dynamic>? classroom;
  final Map<String, dynamic>? school;

  @override
  Future<Map<String, dynamic>?> fetchOwnStudent() async => student;

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
    final repository = RemoteProfileRepository(
      _FakeDataSource(student: student, classroom: classroom, school: school),
    );

    final profile = await repository.loadProfile();

    expect(profile.name, 'Aluno Remoto');
    expect(profile.pointsStudentBalance, 760);
    expect(profile.pointsClassBalance, 1190);
    expect(profile.schoolName, 'Escola Remota');
    expect(profile.className, '9º Ano A');
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
}
