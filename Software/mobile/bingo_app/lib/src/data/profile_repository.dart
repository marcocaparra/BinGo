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

class ProfileCustomization {
  const ProfileCustomization({
    this.avatarId = 'b1n-default',
    this.themeId = 'city-blue',
  });

  final String avatarId;
  final String themeId;

  ProfileCustomization copyWith({String? avatarId, String? themeId}) {
    return ProfileCustomization(
      avatarId: avatarId ?? this.avatarId,
      themeId: themeId ?? this.themeId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProfileCustomization &&
        other.avatarId == avatarId &&
        other.themeId == themeId;
  }

  @override
  int get hashCode => Object.hash(avatarId, themeId);
}

abstract interface class ProfileCustomizationStore {
  Future<ProfileCustomization> loadCustomization();

  Future<void> saveCustomization(ProfileCustomization customization);
}

abstract class ProfileRepository {
  Future<void> deleteProfile();

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

class LocalProfileRepository
    implements ProfileRepository, ProfileCustomizationStore {
  const LocalProfileRepository(this._preferences);

  static const _schoolKey = 'bingo.profile.school';
  static const _identifierKey = 'bingo.profile.identifier';
  static const _pinKey = 'bingo.profile.pin';
  static const _avatarKey = 'bingo.profile.avatar';
  static const _themeKey = 'bingo.profile.theme';

  final SharedPreferences _preferences;

  @override
  Future<void> deleteProfile() async {
    await _preferences.remove(_schoolKey);
    await _preferences.remove(_identifierKey);
    await _preferences.remove(_pinKey);
    await _preferences.remove(_avatarKey);
    await _preferences.remove(_themeKey);
  }

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
  Future<ProfileCustomization> loadCustomization() async {
    return ProfileCustomization(
      avatarId: _preferences.getString(_avatarKey) ?? 'b1n-default',
      themeId: _preferences.getString(_themeKey) ?? 'city-blue',
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
  Future<void> saveCustomization(ProfileCustomization customization) async {
    await _preferences.setString(_avatarKey, customization.avatarId);
    await _preferences.setString(_themeKey, customization.themeId);
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
    final matchesProfile =
        _preferences.getString(_schoolKey) == school.trim() &&
        _preferences.getString(_identifierKey) == identifier.trim();

    if (!matchesProfile) {
      return false;
    }

    await _preferences.setString(_pinKey, newPin);
    return true;
  }
}

class SharedPreferencesCustomizationStore implements ProfileCustomizationStore {
  const SharedPreferencesCustomizationStore(this._preferences);

  static const _avatarKey = 'bingo.profile.avatar';
  static const _themeKey = 'bingo.profile.theme';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesCustomizationStore> create() async {
    return SharedPreferencesCustomizationStore(
      await SharedPreferences.getInstance(),
    );
  }

  @override
  Future<ProfileCustomization> loadCustomization() async {
    return ProfileCustomization(
      avatarId: _preferences.getString(_avatarKey) ?? 'b1n-default',
      themeId: _preferences.getString(_themeKey) ?? 'city-blue',
    );
  }

  @override
  Future<void> saveCustomization(ProfileCustomization customization) async {
    await _preferences.setString(_avatarKey, customization.avatarId);
    await _preferences.setString(_themeKey, customization.themeId);
  }
}

class AuthenticatedStudentProfile {
  const AuthenticatedStudentProfile({
    required this.id,
    required this.name,
    required this.schoolId,
    required this.schoolName,
    required this.classId,
    required this.className,
    required this.pointsStudentBalance,
    required this.pointsClassBalance,
    required this.status,
  });

  final String id;
  final String name;
  final String schoolId;
  final String schoolName;
  final String classId;
  final String className;
  final int pointsStudentBalance;
  final int pointsClassBalance;
  final String status;

  int get binCoinsBalance => pointsStudentBalance;

  int get classXpBalance => pointsClassBalance;
}

enum ProfileFailureKind {
  network,
  sessionInvalid,
  authLinkMissing,
  notFound,
  malformedData,
  unknown,
}

class ProfileFailure implements Exception {
  const ProfileFailure(this.kind, this.message, [this.cause]);

  final ProfileFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class AuthenticatedProfileRepository {
  Future<AuthenticatedStudentProfile> loadProfile();
}
