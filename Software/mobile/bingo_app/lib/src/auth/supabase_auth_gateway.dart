import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/deposit_history_repository.dart';
import '../data/binbazar_repository.dart';
import '../data/class_journey_repository.dart';
import '../data/missions_repository.dart';
import '../data/profile_repository.dart';
import '../data/ranking_repository.dart';
import '../data/supabase_deposit_history_repository.dart';
import '../data/supabase_binbazar_repository.dart';
import '../data/supabase_class_journey_repository.dart';
import '../data/supabase_missions_repository.dart';
import '../data/supabase_profile_repository.dart';
import '../data/supabase_ranking_repository.dart';
import 'auth_gateway.dart';

class SupabaseAuthGatewayFactory implements AuthGatewayFactory {
  SupabaseAuthGatewayFactory(this._config);

  final SupabaseConfig _config;
  AuthGateway? _gateway;

  static SupabaseClient? _initializedClient;

  @override
  Future<AuthGateway> create() async {
    final existing = _gateway;
    if (existing != null) return existing;

    if (!_config.isConfigured) {
      throw SupabaseConfigurationException(_config.missingVariables);
    }

    final client = _initializedClient ??= await _initializeClient();
    return _gateway = SupabaseAuthGateway(client);
  }

  Future<SupabaseClient> _initializeClient() async {
    await Supabase.initialize(
      url: _config.url,
      publishableKey: _config.publishableKey,
    );
    return Supabase.instance.client;
  }
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client)
    : _binBazarRepository = RemoteBinBazarRepository(
        SupabaseBinBazarDataSource(_client),
      ),
      _depositHistoryRepository = RemoteDepositHistoryRepository(
        SupabaseDepositHistoryDataSource(_client),
      ),
      _profileRepository = RemoteProfileRepository(
        SupabaseProfileDataSource(_client),
      ),
      _rankingRepository = RemoteRankingRepository(
        SupabaseRankingDataSource(_client),
      ),
      _missionsRepository = RemoteMissionsRepository(
        SupabaseMissionsDataSource(_client),
      ),
      _journeyRepository = RemoteClassJourneyRepository(
        SupabaseClassJourneyDataSource(_client),
      ) {
    _authSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        _sessionEvents.add(AuthSessionEvent.networkError);
      },
    );
  }

  final SupabaseClient _client;
  final AuthenticatedBinBazarRepository _binBazarRepository;
  final AuthenticatedDepositHistoryRepository _depositHistoryRepository;
  final AuthenticatedMissionsRepository _missionsRepository;
  final AuthenticatedClassJourneyRepository _journeyRepository;
  final AuthenticatedProfileRepository _profileRepository;
  final AuthenticatedRankingRepository _rankingRepository;
  final StreamController<AuthSessionEvent> _sessionEvents =
      StreamController<AuthSessionEvent>.broadcast();
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  AuthenticatedBinBazarRepository get binBazarRepository => _binBazarRepository;

  @override
  AuthenticatedDepositHistoryRepository get depositHistoryRepository =>
      _depositHistoryRepository;

  @override
  AuthenticatedMissionsRepository get missionsRepository => _missionsRepository;

  @override
  AuthenticatedClassJourneyRepository get journeyRepository =>
      _journeyRepository;

  @override
  AuthenticatedProfileRepository get profileRepository => _profileRepository;

  @override
  AuthenticatedRankingRepository get rankingRepository => _rankingRepository;

  @override
  Stream<AuthSessionEvent> get sessionEvents => _sessionEvents.stream;

  @override
  Future<bool> restoreSession() async {
    return _client.auth.currentSession != null &&
        _client.auth.currentUser != null;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.session == null || response.user == null) {
        throw const AuthFailure(
          AuthFailureKind.sessionInvalid,
          'O Supabase não retornou uma sessão válida.',
        );
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      final normalized = error.message.toLowerCase();
      if (normalized.contains('invalid login credentials') ||
          normalized.contains('invalid credentials')) {
        throw AuthFailure(
          AuthFailureKind.invalidCredentials,
          'E-mail ou senha inválidos.',
          error,
        );
      }
      if (_looksLikeNetworkFailure(normalized)) {
        throw AuthFailure(
          AuthFailureKind.network,
          'Não foi possível entrar. Verifique sua conexão.',
          error,
        );
      }
      throw AuthFailure(
        AuthFailureKind.unknown,
        'Não foi possível autenticar agora.',
        error,
      );
    } catch (error) {
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw AuthFailure(
          AuthFailureKind.network,
          'Não foi possível entrar. Verifique sua conexão.',
          error,
        );
      }
      throw AuthFailure(
        AuthFailureKind.unknown,
        'Não foi possível autenticar agora.',
        error,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      final normalized = error.toString().toLowerCase();
      if (_looksLikeNetworkFailure(normalized)) {
        throw AuthFailure(
          AuthFailureKind.network,
          'Não foi possível encerrar a sessão. Verifique sua conexão.',
          error,
        );
      }
      throw AuthFailure(
        AuthFailureKind.unknown,
        'Não foi possível encerrar a sessão agora.',
        error,
      );
    }
  }

  @override
  Future<void> close() async {
    await _authSubscription.cancel();
    await _sessionEvents.close();
  }

  void _handleAuthState(AuthState state) {
    if (state.event == AuthChangeEvent.signedOut) {
      _sessionEvents.add(AuthSessionEvent.signedOut);
    }
  }
}

bool _looksLikeNetworkFailure(String message) {
  return message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('failed host') ||
      message.contains('clientexception') ||
      message.contains('timeout');
}
