import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AccessRestoreStore {
  Future<bool> shouldRestoreAuthenticatedSession();

  Future<void> markAuthenticatedSession();

  Future<void> clearAuthenticatedSession();
}

class SharedPreferencesAccessRestoreStore implements AccessRestoreStore {
  const SharedPreferencesAccessRestoreStore();

  static const _restoreKey = 'bingo.access.restore_authenticated';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<void> clearAuthenticatedSession() async {
    await (await _preferences).remove(_restoreKey);
  }

  @override
  Future<void> markAuthenticatedSession() async {
    await (await _preferences).setBool(_restoreKey, true);
  }

  @override
  Future<bool> shouldRestoreAuthenticatedSession() async {
    return (await _preferences).getBool(_restoreKey) ?? false;
  }
}
