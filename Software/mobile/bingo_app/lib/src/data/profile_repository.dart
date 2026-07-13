import 'package:shared_preferences/shared_preferences.dart';

class StudentProfile {
  const StudentProfile({required this.school, required this.identifier});

  final String school;
  final String identifier;

  @override
  bool operator ==(Object other) {
    return other is StudentProfile &&
        other.school == school &&
        other.identifier == identifier;
  }

  @override
  int get hashCode => Object.hash(school, identifier);
}

abstract class ProfileRepository {
  Future<bool> hasProfile();

  Future<StudentProfile?> loadProfile();

  Future<void> save({required StudentProfile profile, required String pin});

  Future<bool> verify({
    required String school,
    required String identifier,
    required String pin,
  });

  Future<bool> resetPin({
    required String school,
    required String identifier,
    required String newPin,
  });
}

class LocalProfileRepository implements ProfileRepository {
  const LocalProfileRepository(this._preferences);

  static const _schoolKey = 'bingo.profile.school';
  static const _identifierKey = 'bingo.profile.identifier';
  static const _pinKey = 'bingo.profile.pin';

  final SharedPreferences _preferences;

  @override
  Future<bool> hasProfile() async {
    return _preferences.containsKey(_schoolKey) &&
        _preferences.containsKey(_identifierKey) &&
        _preferences.containsKey(_pinKey);
  }

  @override
  Future<StudentProfile?> loadProfile() async {
    if (!await hasProfile()) {
      return null;
    }

    return StudentProfile(
      school: _preferences.getString(_schoolKey)!,
      identifier: _preferences.getString(_identifierKey)!,
    );
  }

  @override
  Future<void> save({
    required StudentProfile profile,
    required String pin,
  }) async {
    await _preferences.setString(_schoolKey, profile.school.trim());
    await _preferences.setString(_identifierKey, profile.identifier.trim());
    await _preferences.setString(_pinKey, pin);
  }

  @override
  Future<bool> verify({
    required String school,
    required String identifier,
    required String pin,
  }) async {
    return _preferences.getString(_schoolKey) == school.trim() &&
        _preferences.getString(_identifierKey) == identifier.trim() &&
        _preferences.getString(_pinKey) == pin;
  }

  @override
  Future<bool> resetPin({
    required String school,
    required String identifier,
    required String newPin,
  }) async {
    final matchesProfile = _preferences.getString(_schoolKey) == school.trim() &&
        _preferences.getString(_identifierKey) == identifier.trim();

    if (!matchesProfile) {
      return false;
    }

    await _preferences.setString(_pinKey, newPin);
    return true;
  }
}
