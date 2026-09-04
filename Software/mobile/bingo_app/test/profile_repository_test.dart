import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:bingo_app/src/data/supabase_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<LocalProfileRepository> repositoryWithEmptyStorage() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    return LocalProfileRepository(preferences);
  }

  test('saves a local profile and verifies its PIN', () async {
    final repository = await repositoryWithEmptyStorage();
    const profile = StudentProfile(school: 'ENIAC', identifier: '2026001');

    await repository.save(profile: profile, pin: '4826');

    expect(await repository.hasProfile(), isTrue);
    expect(await repository.loadProfile(), profile);
    expect(
      await repository.verify(
        school: 'ENIAC',
        identifier: '2026001',
        pin: '4826',
      ),
      isTrue,
    );
  });

  test('rejects an incorrect PIN without deleting the saved profile', () async {
    final repository = await repositoryWithEmptyStorage();
    const profile = StudentProfile(school: 'ENIAC', identifier: '2026001');
    await repository.save(profile: profile, pin: '4826');

    final authenticated = await repository.verify(
      school: 'ENIAC',
      identifier: '2026001',
      pin: '9999',
    );

    expect(authenticated, isFalse);
    expect(await repository.loadProfile(), profile);
  });

  test(
    'replaces the previous PIN after a reset for the saved student',
    () async {
      final repository = await repositoryWithEmptyStorage();
      const profile = StudentProfile(school: 'ENIAC', identifier: '2026001');
      await repository.save(profile: profile, pin: '4826');

      final reset = await repository.resetPin(
        school: 'ENIAC',
        identifier: '2026001',
        newPin: '1357',
      );

      expect(reset, isTrue);
      expect(
        await repository.verify(
          school: 'ENIAC',
          identifier: '2026001',
          pin: '4826',
        ),
        isFalse,
      );
      expect(
        await repository.verify(
          school: 'ENIAC',
          identifier: '2026001',
          pin: '1357',
        ),
        isTrue,
      );
    },
  );

  test('deletes the local profile and its PIN', () async {
    final repository = await repositoryWithEmptyStorage();
    await repository.save(
      profile: const StudentProfile(school: 'ENIAC', identifier: '2026001'),
      pin: '4826',
    );

    await repository.deleteProfile();

    expect(await repository.hasProfile(), isFalse);
    expect(await repository.loadProfile(), isNull);
  });

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

  test(
    'repository remoto filtra e mapeia somente o perfil autenticado',
    () async {
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
    },
  );

  test(
    'repository remoto rejeita sessão ou usuário corrente ausente',
    () async {
      for (final dataSource in [
        _FakeDataSource(hasSession: false),
        _FakeDataSource(currentUserId: null),
      ]) {
        await expectLater(
          RemoteProfileRepository(dataSource).loadProfile(),
          throwsA(
            isA<ProfileFailure>().having(
              (failure) => failure.kind,
              'kind',
              ProfileFailureKind.sessionInvalid,
            ),
          ),
        );
      }
    },
  );

  test('repository remoto diferencia aluno Auth sem vínculo', () async {
    await expectLater(
      RemoteProfileRepository(_FakeDataSource()).loadProfile(),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.authLinkMissing,
        ),
      ),
    );
  });

  test('repository remoto rejeita relações e saldos inválidos', () async {
    final invalidSources = [
      _FakeDataSource(
        student: student,
        classroom: {...classroom, 'school_id': 'another-school'},
        school: school,
      ),
      _FakeDataSource(student: student, classroom: classroom),
      _FakeDataSource(
        student: {...student, 'points_student_balance': null},
        classroom: classroom,
        school: school,
      ),
    ];

    for (final dataSource in invalidSources) {
      await expectLater(
        RemoteProfileRepository(dataSource).loadProfile(),
        throwsA(isA<ProfileFailure>()),
      );
    }
  });
}
