enum AccessPhase {
  initializing,
  unauthenticated,
  pilot,
  authenticated,
  initializationError,
}

class AccessState {
  const AccessState._(this.phase, {this.message});

  const AccessState.initializing() : this._(AccessPhase.initializing);

  const AccessState.unauthenticated() : this._(AccessPhase.unauthenticated);

  const AccessState.pilot() : this._(AccessPhase.pilot);

  const AccessState.authenticated() : this._(AccessPhase.authenticated);

  const AccessState.initializationError(String message)
    : this._(AccessPhase.initializationError, message: message);

  final AccessPhase phase;
  final String? message;
}
