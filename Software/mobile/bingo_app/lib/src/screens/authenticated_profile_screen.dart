import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_gateway.dart';
import '../data/profile_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';

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

    final profile = _profile!;
    return Column(
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('Status: ${profile.status}'),
              const Divider(height: 28),
              _ProfileRow(label: 'Escola', value: profile.schoolName),
              _ProfileRow(label: 'Turma', value: profile.className),
              _ProfileRow(
                label: 'Pontos pessoais',
                value: profile.pointsStudentBalance.toString(),
              ),
              _ProfileRow(
                label: 'Pontos da turma',
                value: profile.pointsClassBalance.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SurfaceCard(
          color: Color(0xFFF1F8FD),
          child: Text(
            'Níveis, conquistas, BinCoins e métricas ambientais não estão disponíveis no perfil autenticado nesta etapa.',
          ),
        ),
        if (_loggingOut) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
        if (_logoutError != null) ...[
          const SizedBox(height: 12),
          Text(_logoutError!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
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
