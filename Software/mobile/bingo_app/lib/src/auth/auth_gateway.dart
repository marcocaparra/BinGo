import '../data/profile_repository.dart';

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
  AuthenticatedProfileRepository get profileRepository;

  Stream<AuthSessionEvent> get sessionEvents;

  Future<bool> restoreSession();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> close();
}

abstract interface class AuthGatewayFactory {
  Future<AuthGateway> create();
}
