import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/access_restore_store.dart';
import 'auth/access_state.dart';
import 'auth/auth_gateway.dart';
import 'auth/supabase_auth_gateway.dart';
import 'config/supabase_config.dart';
import 'data/profile_repository.dart';
import 'screens/access_flow_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

class BingoApp extends StatelessWidget {
  const BingoApp({
    this.repository,
    this.authGatewayFactory,
    this.restoreStore,
    super.key,
  });

  final ProfileRepository? repository;
  final AuthGatewayFactory? authGatewayFactory;
  final AccessRestoreStore? restoreStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BinGo!',
      theme: AppTheme.light(),
      home: SessionGate(
        repository: repository,
        authGatewayFactory:
            authGatewayFactory ??
            SupabaseAuthGatewayFactory(SupabaseConfig.fromEnvironment()),
        restoreStore: restoreStore,
      ),
    );
  }
}

class SessionGate extends StatefulWidget {
  SessionGate({
    this.repository,
    AuthGatewayFactory? authGatewayFactory,
    this.restoreStore,
    super.key,
  }) : authGatewayFactory =
           authGatewayFactory ??
           SupabaseAuthGatewayFactory(SupabaseConfig.fromEnvironment());

  final ProfileRepository? repository;
  final AuthGatewayFactory authGatewayFactory;
  final AccessRestoreStore? restoreStore;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ({AccessState access, ProfileRepository localRepository})? _session;
  AccessRestoreStore? _restoreStore;
  AuthGateway? _gateway;
  StreamSubscription<AuthSessionEvent>? _sessionSubscription;
  Object? _error;
  bool _started = false;

  Future<AccessRestoreStore> _store() async {
    final existing = _restoreStore;
    if (existing != null) return existing;
    return _restoreStore =
        widget.restoreStore ?? const SharedPreferencesAccessRestoreStore();
  }

  Future<ProfileRepository> _localRepository() async {
    return widget.repository ??
        LocalProfileRepository(await SharedPreferences.getInstance());
  }

  Future<AuthGateway> _createGateway() async {
    final existing = _gateway;
    if (existing != null) return existing;
    final gateway = await widget.authGatewayFactory.create();
    _gateway = gateway;
    _sessionSubscription = gateway.sessionEvents.listen(_handleSessionEvent);
    return gateway;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    unawaited(_startSession());
  }

  Future<({AccessState access, ProfileRepository localRepository})>
  _resolveSession() async {
    final localRepository = await _localRepository();
    final store = await _store();
    final expectedAuthenticatedSession = await store
        .shouldRestoreAuthenticatedSession();

    try {
      final gateway = await _createGateway();
      if (await gateway.restoreSession()) {
        await store.markAuthenticatedSession();
        return (
          access: const AccessState.authenticated(),
          localRepository: localRepository,
        );
      }
      await store.clearAuthenticatedSession();
    } on SupabaseConfigurationException catch (error) {
      if (expectedAuthenticatedSession) rethrow;
      _error = error;
    }

    final hasLocalProfile = await localRepository.hasProfile();
    return (
      access: hasLocalProfile
          ? const AccessState.pilot()
          : const AccessState.unauthenticated(),
      localRepository: localRepository,
    );
  }

  Future<void> _startSession() async {
    _started = true;
    _session = null;
    _error = null;
    if (mounted) setState(() {});
    try {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final sessionFuture = _resolveSession();
      if (!reduceMotion) await WidgetsBinding.instance.endOfFrame;
      final results = await Future.wait<dynamic>([
        sessionFuture,
        if (!reduceMotion)
          Future<void>.delayed(const Duration(milliseconds: 2800)),
      ]);
      if (!mounted) return;
      setState(() {
        _session =
            results.first
                as ({AccessState access, ProfileRepository localRepository});
      });
    } on SupabaseConfigurationException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.userMessage);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Não foi possível restaurar a sessão. Verifique sua conexão.',
      );
    }
  }

  Future<AuthFailure?> _signIn(String email, String password) async {
    try {
      final gateway = await _createGateway();
      await gateway.signIn(email: email, password: password);
      await (await _store()).markAuthenticatedSession();
      final localRepository =
          _session?.localRepository ?? await _localRepository();
      if (mounted) {
        setState(() {
          _session = (
            access: const AccessState.authenticated(),
            localRepository: localRepository,
          );
        });
      }
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
    final localRepository =
        _session?.localRepository ?? await _localRepository();
    if (!mounted) return;
    setState(() {
      _session = (
        access: const AccessState.unauthenticated(),
        localRepository: localRepository,
      );
      _error = null;
    });
  }

  void _enterPilot() {
    final session = _session;
    if (session == null) return;
    setState(() {
      _session = (
        access: const AccessState.pilot(),
        localRepository: session.localRepository,
      );
      _error = null;
    });
  }

  void _handleSessionEvent(AuthSessionEvent event) {
    switch (event) {
      case AuthSessionEvent.signedOut || AuthSessionEvent.sessionInvalid:
        unawaited(_returnToEntry());
      case AuthSessionEvent.networkError:
        break;
    }
  }

  void _retry() {
    _started = false;
    unawaited(_startSession());
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    unawaited(_gateway?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final destination = session == null
        ? SplashScreen(error: _error, onRetry: _error == null ? null : _retry)
        : switch (session.access.phase) {
            AccessPhase.authenticated => ShellScreen.authenticated(
              key: const ValueKey('authenticated-shell'),
              repository: _gateway!.profileRepository,
              onLogout: _signOut,
              onSessionInvalid: _returnToEntry,
            ),
            AccessPhase.pilot => ShellScreen(
              key: const ValueKey('local-shell'),
              repository: session.localRepository,
              onExitPilot: _returnToEntry,
            ),
            AccessPhase.unauthenticated => AccessFlowScreen(
              key: const ValueKey('access-flow'),
              repository: session.localRepository,
              onEmailSignIn: _signIn,
              onEnterPilot: _enterPilot,
            ),
            AccessPhase.initializing => const SplashScreen(),
            AccessPhase.initializationError => SplashScreen(
              error: session.access.message,
              onRetry: _retry,
            ),
          };

    return AnimatedSwitcher(
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context)
            ? 0
            : AppMotion.standard,
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: (currentChild, previousChildren) => ColoredBox(
        color: AppColors.surface,
        child: currentChild ?? const SizedBox.expand(),
      ),
      child: destination,
    );
  }
}
