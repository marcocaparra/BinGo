import '../data/deposit_history_repository.dart';
import '../data/missions_repository.dart';
import '../data/profile_repository.dart';
import '../data/ranking_repository.dart';

enum AuthFailureKind {
  invalidCredentials,
  network,
  missingConfiguration,
  sessionInvalid,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message, [this.cause]);

  final AuthFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

enum AuthSessionEvent { signedOut, sessionInvalid, networkError }

abstract interface class AuthGateway {
  AuthenticatedDepositHistoryRepository get depositHistoryRepository;

  AuthenticatedMissionsRepository get missionsRepository;

  AuthenticatedProfileRepository get profileRepository;

  AuthenticatedRankingRepository get rankingRepository;

  Stream<AuthSessionEvent> get sessionEvents;

  Future<bool> restoreSession();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> close();
}

abstract interface class AuthGatewayFactory {
  Future<AuthGateway> create();
}
