import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('replaces the previous PIN after a reset for the saved student', () async {
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
  });

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
}
