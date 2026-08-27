import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/profile_repository.dart';
import 'screens/access_flow_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

class BingoApp extends StatelessWidget {
  const BingoApp({this.repository, super.key});

  final ProfileRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BinGo!',
      theme: AppTheme.light(),
      home: SessionGate(repository: repository),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({this.repository, super.key});

  final ProfileRepository? repository;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ({ProfileRepository repository, bool hasProfile})? _session;
  Object? _error;
  bool _started = false;

  Future<({ProfileRepository repository, bool hasProfile})>
  _resolveSession() async {
    final repository =
        widget.repository ??
        LocalProfileRepository(await SharedPreferences.getInstance());
    return (repository: repository, hasProfile: await repository.hasProfile());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _startSession();
  }

  Future<void> _startSession() async {
    _started = true;
    setState(() => _error = null);
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
            results.first as ({ProfileRepository repository, bool hasProfile});
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _retry() {
    _started = false;
    _startSession();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final destination = session == null
        ? SplashScreen(error: _error, onRetry: _error == null ? null : _retry)
        : session.hasProfile
        ? ShellScreen(
            key: const ValueKey('shell'),
            repository: session.repository,
          )
        : AccessFlowScreen(
            key: const ValueKey('access-flow'),
            repository: session.repository,
          );

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
