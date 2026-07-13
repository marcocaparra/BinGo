import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/profile_repository.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
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
  late final Future<({ProfileRepository repository, bool hasProfile})> _session =
      _resolveSession();

  Future<({ProfileRepository repository, bool hasProfile})> _resolveSession() async {
    final repository = widget.repository ??
        LocalProfileRepository(await SharedPreferences.getInstance());
    return (repository: repository, hasProfile: await repository.hasProfile());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({ProfileRepository repository, bool hasProfile})>(
      future: _session,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.requireData;
        if (session.hasProfile) {
          return ShellScreen(repository: session.repository);
        }
        return OnboardingScreen(repository: session.repository);
      },
    );
  }
}
