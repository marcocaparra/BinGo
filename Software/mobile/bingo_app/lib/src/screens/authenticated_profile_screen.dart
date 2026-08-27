import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_gateway.dart';
import '../data/profile_repository.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import 'profile_screen.dart';

class AuthenticatedProfileScreen extends StatefulWidget {
  const AuthenticatedProfileScreen({
    required this.repository,
    required this.onSessionInvalid,
    required this.onLogout,
    super.key,
  });

  final ProfileRepository repository;
  final Future<void> Function() onSessionInvalid;
  final Future<AuthFailure?> Function() onLogout;

  @override
  State<AuthenticatedProfileScreen> createState() =>
      _AuthenticatedProfileScreenState();
}

class _AuthenticatedProfileScreenState
    extends State<AuthenticatedProfileScreen> {
  StudentProfile? _profile;
  ProfileFailure? _failure;
  var _loading = true;
  var _loggingOut = false;
  String? _logoutError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final profile = await widget.repository.loadProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on ProfileFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _failure = failure;
        _loading = false;
      });
      if (failure.kind == ProfileFailureKind.sessionInvalid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(widget.onSessionInvalid());
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _failure = ProfileFailure(
          ProfileFailureKind.unknown,
          'Não foi possível carregar o perfil agora.',
          error,
        );
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() {
      _loggingOut = true;
      _logoutError = null;
    });
    final failure = await widget.onLogout();
    if (!mounted || failure == null) return;
    setState(() {
      _loggingOut = false;
      _logoutError = failure.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (!_loading && _failure == null && profile != null) {
      return ProfileScreen.authenticated(
        profile: profile,
        onLogout: _logout,
        loggingOut: _loggingOut,
        logoutError: _logoutError,
      );
    }

    return AppPage(
      title: 'Perfil autenticado',
      subtitle: 'Dados reais da conta vinculada no Supabase.',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      actions: [
        IconButton(
          tooltip: 'Sair da conta',
          onPressed: _loggingOut ? null : _logout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const BingoDataState(
        kind: BingoDataStateKind.loading,
        title: 'Carregando perfil',
        message: 'Consultando os dados permitidos para esta sessão.',
      );
    }

    final failure = _failure;
    if (failure != null) {
      return BingoDataState(
        key: ValueKey('profile-error-${failure.kind.name}'),
        kind: BingoDataStateKind.empty,
        title: _failureTitle(failure.kind),
        message: failure.message,
        icon: _failureIcon(failure.kind),
        action: failure.kind == ProfileFailureKind.sessionInvalid
            ? null
            : BingoActionButton(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
      );
    }

    return const SizedBox.shrink();
  }
}

String _failureTitle(ProfileFailureKind kind) {
  return switch (kind) {
    ProfileFailureKind.network => 'Sem conexão com o perfil',
    ProfileFailureKind.sessionInvalid => 'Sessão expirada',
    ProfileFailureKind.authLinkMissing => 'Conta sem vínculo de aluno',
    ProfileFailureKind.notFound => 'Perfil incompleto',
    ProfileFailureKind.malformedData => 'Perfil remoto inválido',
    ProfileFailureKind.unknown => 'Erro ao carregar perfil',
  };
}

IconData _failureIcon(ProfileFailureKind kind) {
  return switch (kind) {
    ProfileFailureKind.network => Icons.cloud_off_rounded,
    ProfileFailureKind.sessionInvalid => Icons.lock_clock_outlined,
    ProfileFailureKind.authLinkMissing => Icons.link_off_rounded,
    ProfileFailureKind.notFound => Icons.person_search_outlined,
    ProfileFailureKind.malformedData => Icons.warning_amber_rounded,
    ProfileFailureKind.unknown => Icons.error_outline_rounded,
  };
}
