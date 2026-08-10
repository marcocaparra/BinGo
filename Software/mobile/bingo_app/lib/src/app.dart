import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/access_restore_store.dart';
import 'auth/access_state.dart';
import 'auth/auth_gateway.dart';
import 'auth/supabase_auth_gateway.dart';
import 'config/supabase_config.dart';
import 'screens/authenticated_profile_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'theme/app_theme.dart';

class BingoApp extends StatefulWidget {
  const BingoApp({this.authGatewayFactory, this.restoreStore, super.key});

  final AuthGatewayFactory? authGatewayFactory;
  final AccessRestoreStore? restoreStore;

  @override
  State<BingoApp> createState() => _BingoAppState();
}

class _BingoAppState extends State<BingoApp> {
  late final AuthGatewayFactory _authGatewayFactory =
      widget.authGatewayFactory ??
      SupabaseAuthGatewayFactory(SupabaseConfig.fromEnvironment());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BinGo!',
      theme: AppTheme.light(),
      home: SessionGate(
        authGatewayFactory: _authGatewayFactory,
        restoreStore: widget.restoreStore,
      ),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({
    required this.authGatewayFactory,
    this.restoreStore,
    super.key,
  });

  final AuthGatewayFactory authGatewayFactory;
  final AccessRestoreStore? restoreStore;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  AccessState _access = const AccessState.initializing();
  AccessRestoreStore? _restoreStore;
  AuthGateway? _gateway;
  StreamSubscription<AuthSessionEvent>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAccess());
  }

  Future<AccessRestoreStore> _store() async {
    final existing = _restoreStore;
    if (existing != null) return existing;
    return _restoreStore =
        widget.restoreStore ?? const SharedPreferencesAccessRestoreStore();
  }

  Future<AuthGateway> _createGateway() async {
    final existing = _gateway;
    if (existing != null) return existing;
    final gateway = await widget.authGatewayFactory.create();
    _gateway = gateway;
    _sessionSubscription = gateway.sessionEvents.listen(_handleSessionEvent);
    return gateway;
  }

  Future<void> _restoreAccess() async {
    if (mounted) setState(() => _access = const AccessState.initializing());
    final store = await _store();
    if (!await store.shouldRestoreAuthenticatedSession()) {
      if (mounted) {
        setState(() => _access = const AccessState.unauthenticated());
      }
      return;
    }

    try {
      final gateway = await _createGateway();
      if (!await gateway.restoreSession()) {
        await store.clearAuthenticatedSession();
        if (mounted) {
          setState(() => _access = const AccessState.unauthenticated());
        }
        return;
      }
      if (mounted) setState(() => _access = const AccessState.authenticated());
    } on SupabaseConfigurationException catch (error) {
      if (mounted) {
        setState(
          () => _access = AccessState.initializationError(error.userMessage),
        );
      }
    } on AuthFailure catch (error) {
      if (mounted) {
        setState(
          () => _access = AccessState.initializationError(error.message),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _access = const AccessState.initializationError(
            'Não foi possível restaurar a sessão. Verifique sua conexão.',
          ),
        );
      }
    }
  }

  Future<AuthFailure?> _signIn(String email, String password) async {
    try {
      final gateway = await _createGateway();
      await gateway.signIn(email: email, password: password);
      await (await _store()).markAuthenticatedSession();
      if (mounted) setState(() => _access = const AccessState.authenticated());
      return null;
    } on SupabaseConfigurationException catch (error) {
      return AuthFailure(
        AuthFailureKind.missingConfiguration,
        error.userMessage,
        error,
      );
    } on AuthFailure catch (error) {
      return error;
    } catch (error) {
      return AuthFailure(
        AuthFailureKind.unknown,
        'Não foi possível autenticar agora.',
        error,
      );
    }
  }

  void _enterPilot() {
    setState(() => _access = const AccessState.pilot());
  }

  Future<void> _leavePilot() async {
    setState(() => _access = const AccessState.unauthenticated());
  }

  Future<AuthFailure?> _signOut() async {
    final gateway = _gateway;
    if (gateway == null) {
      await _returnToEntry();
      return null;
    }
    try {
      await gateway.signOut();
      await _returnToEntry();
      return null;
    } on AuthFailure catch (error) {
      return error;
    } catch (error) {
      return AuthFailure(
        AuthFailureKind.unknown,
        'Não foi possível sair agora.',
        error,
      );
    }
  }

  Future<void> _returnToEntry() async {
    await (await _store()).clearAuthenticatedSession();
    if (mounted) setState(() => _access = const AccessState.unauthenticated());
  }

  void _handleSessionEvent(AuthSessionEvent event) {
    switch (event) {
      case AuthSessionEvent.signedOut || AuthSessionEvent.sessionInvalid:
        unawaited(_returnToEntry());
      case AuthSessionEvent.networkError:
        if (mounted) {
          setState(
            () => _access = const AccessState.initializationError(
              'A sessão não pôde ser atualizada. Verifique sua conexão e tente novamente.',
            ),
          );
        }
    }
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    unawaited(_gateway?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_access.phase) {
      AccessPhase.initializing => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AccessPhase.unauthenticated => OnboardingScreen(
        onSignIn: _signIn,
        onEnterPilot: _enterPilot,
      ),
      AccessPhase.pilot => ShellScreen(onExitPilot: _leavePilot),
      AccessPhase.authenticated => AuthenticatedProfileScreen(
        repository: _gateway!.profileRepository,
        onSessionInvalid: _returnToEntry,
        onLogout: _signOut,
      ),
      AccessPhase.initializationError => _InitializationErrorScreen(
        message: _access.message!,
        onRetry: _restoreAccess,
        onReturnToEntry: _returnToEntry,
      ),
    };
  }
}

class _InitializationErrorScreen extends StatelessWidget {
  const _InitializationErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onReturnToEntry,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReturnToEntry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
                TextButton(
                  onPressed: onReturnToEntry,
                  child: const Text('Voltar para a entrada'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
