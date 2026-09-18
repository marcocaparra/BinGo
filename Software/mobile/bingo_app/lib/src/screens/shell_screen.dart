import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/auth_gateway.dart';
import '../data/demo_data.dart';
import '../data/deposit_history_adapter.dart';
import '../data/deposit_history_repository.dart';
import '../data/missions_repository.dart';
import '../data/profile_repository.dart';
import '../data/session_wallet_controller.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_navigation_bar.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import '../widgets/periodic_highlight.dart';
import 'city_map_screen.dart';
import 'profile_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({
    this.initialIndex = 0,
    this.repository,
    this.onExitPilot,
    super.key,
  }) : authenticatedRepository = null,
       depositHistoryRepository = null,
       missionsRepository = null,
       onLogout = null,
       onSessionInvalid = null;

  const ShellScreen.authenticated({
    required AuthenticatedProfileRepository repository,
    required this.depositHistoryRepository,
    required this.missionsRepository,
    required this.onLogout,
    required this.onSessionInvalid,
    this.initialIndex = 0,
    super.key,
  }) : authenticatedRepository = repository,
       repository = null,
       onExitPilot = null;

  final int initialIndex;
  final ProfileRepository? repository;
  final Future<void> Function()? onExitPilot;
  final AuthenticatedProfileRepository? authenticatedRepository;
  final AuthenticatedDepositHistoryRepository? depositHistoryRepository;
  final AuthenticatedMissionsRepository? missionsRepository;
  final Future<AuthFailure?> Function()? onLogout;
  final Future<void> Function()? onSessionInvalid;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _index = widget.initialIndex;
  String _firstName = 'Marco';
  final SessionWalletController _wallet = SessionWalletController();
  AuthenticatedStudentProfile? _authenticatedProfile;
  ProfileFailure? _profileFailure;
  var _loadingProfile = false;

  @override
  void initState() {
    super.initState();
    if (widget.authenticatedRepository == null && widget.onExitPilot == null) {
      _loadFirstName();
    } else {
      unawaited(_loadAuthenticatedProfile());
    }
  }

  Future<void> _loadFirstName() async {
    final profile = await widget.repository?.loadProfile();
    final identifier = profile?.identifier.trim();
    if (!mounted || identifier == null || identifier.isEmpty) return;
    setState(() => _firstName = identifier.split(RegExp(r'\s+')).first);
  }

  Future<void> _loadAuthenticatedProfile() async {
    if (_loadingProfile) return;
    setState(() {
      _loadingProfile = true;
      _profileFailure = null;
    });
    try {
      final profile = await widget.authenticatedRepository!.loadProfile();
      if (!mounted) return;
      setState(() {
        _authenticatedProfile = profile;
        _loadingProfile = false;
      });
    } on ProfileFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _authenticatedProfile = null;
        _profileFailure = failure;
        _loadingProfile = false;
      });
      if (failure.kind == ProfileFailureKind.sessionInvalid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(widget.onSessionInvalid?.call());
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authenticatedProfile = null;
        _profileFailure = ProfileFailure(
          ProfileFailureKind.unknown,
          'Não foi possível carregar o perfil agora.',
          error,
        );
        _loadingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = widget.authenticatedRepository != null;
    final profile = _authenticatedProfile;
    final failure = _profileFailure;
    final pages = authenticated
        ? profile != null
              ? <Widget>[
                  _AuthenticatedHomeScreen(
                    profile: profile,
                    onOpenTab: _selectTab,
                  ),
                  _AuthenticatedWalletScreen(
                    profile: profile,
                    repository: widget.depositHistoryRepository!,
                    onSessionInvalid: widget.onSessionInvalid!,
                  ),
                  _AuthenticatedMissionsScreen(
                    profile: profile,
                    repository: widget.missionsRepository!,
                    onSessionInvalid: widget.onSessionInvalid!,
                  ),
                  _AuthenticatedRankingScreen(profile: profile),
                  ProfileScreen.authenticated(
                    profile: profile,
                    onLogout: widget.onLogout!,
                    onOpenMissions: () => _selectTab(2),
                  ),
                ]
              : List<Widget>.filled(
                  5,
                  _AuthenticatedProfileState(
                    failure: failure,
                    loading: _loadingProfile,
                    onRetry: _loadAuthenticatedProfile,
                  ),
                )
        : <Widget>[
            HomeScreen(firstName: _firstName, onOpenTab: _selectTab),
            WalletScreen(controller: _wallet),
            const MissionsScreen(),
            RankingScreen(
              isPilot: widget.onExitPilot != null || widget.repository == null,
            ),
            ProfileScreen(
              repository: widget.onExitPilot == null ? widget.repository : null,
              onGoHome: () => _selectTab(0),
              onExitPilot: widget.onExitPilot,
            ),
          ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: BingoNavigationBar(
        selectedIndex: _index,
        onSelected: _selectTab,
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _index = index);
  }
}

class _AuthenticatedProfileState extends StatelessWidget {
  const _AuthenticatedProfileState({
    required this.failure,
    required this.loading,
    required this.onRetry,
  });

  final ProfileFailure? failure;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Sua conta',
      subtitle: 'Dados autorizados pelo Supabase.',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: loading || failure == null
          ? const BingoDataState(
              kind: BingoDataStateKind.loading,
              title: 'Carregando perfil',
              message: 'Consultando os dados permitidos para esta sessão.',
            )
          : BingoDataState(
              kind: BingoDataStateKind.empty,
              title: _profileFailureTitle(failure!.kind),
              message: failure!.message,
              icon: Icons.cloud_off_rounded,
              action: failure!.kind == ProfileFailureKind.sessionInvalid
                  ? null
                  : BingoActionButton(
                      label: 'Tentar novamente',
                      icon: Icons.refresh_rounded,
                      onPressed: onRetry,
                    ),
            ),
    );
  }
}

class _AuthenticatedHomeScreen extends StatelessWidget {
  const _AuthenticatedHomeScreen({
    required this.profile,
    required this.onOpenTab,
  });

  final AuthenticatedStudentProfile profile;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final firstName = profile.name.trim().split(RegExp(r'\s+')).first;
    return AppPage(
      title: 'Olá, $firstName!',
      subtitle: '${profile.schoolName} · ${profile.className}',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: Column(
        children: [
          const ImageHeroCard(
            image: AppAssets.bingopolisMap,
            badge: 'Jornada da turma',
            title: 'Cenário indisponível',
            subtitle:
                'O mapa será exibido quando impacto e progresso tiverem uma fonte autenticada.',
          ),
          const SizedBox(height: 8),
          const B1nDialogueStrip(
            message:
                'Seu perfil está conectado. Consulte as missões ativas da sua escola.',
            portrait: B1nPortraitVariant.instruction,
          ),
          const SizedBox(height: 8),
          const BingoActionButton(
            label: 'Preparo para o Totem indisponível',
            icon: Icons.directions_walk,
            tone: BingoActionTone.green,
            onPressed: null,
          ),
          const SizedBox(height: 18),
          _SoftAction(
            label: 'Ver missões ativas',
            icon: Icons.flag_outlined,
            onTap: () => onOpenTab(2),
          ),
          _SoftAction(
            label: 'Ver ranking indisponível',
            icon: Icons.emoji_events_outlined,
            onTap: () => onOpenTab(3),
          ),
          const _UnavailableSurface(
            title: 'Impacto da turma indisponível',
            message:
                'Nenhum número, cenário ou progresso simulado é atribuído à conta autenticada.',
            icon: Icons.auto_graph_outlined,
          ),
          const SizedBox(height: 12),
          BingoActionButton(
            onPressed: () => _push(context, const HowItWorksScreen()),
            icon: Icons.info_outline,
            label: 'Como funciona o BinGo',
            style: BingoActionStyle.quiet,
          ),
        ],
      ),
    );
  }
}

class _AuthenticatedWalletScreen extends StatefulWidget {
  const _AuthenticatedWalletScreen({
    required this.profile,
    required this.repository,
    required this.onSessionInvalid,
  });

  final AuthenticatedStudentProfile profile;
  final AuthenticatedDepositHistoryRepository repository;
  final Future<void> Function() onSessionInvalid;

  @override
  State<_AuthenticatedWalletScreen> createState() =>
      _AuthenticatedWalletScreenState();
}

class _AuthenticatedWalletScreenState
    extends State<_AuthenticatedWalletScreen> {
  final DepositHistoryAdapter _adapter = DepositHistoryAdapter();
  WalletSection _section = WalletSection.transactions;
  List<DiscardRecord> _discards = const [];
  DepositHistoryFailure? _historyFailure;
  var _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyFailure = null;
    });
    try {
      final history = await widget.repository.loadHistory(
        studentId: widget.profile.id,
      );
      final discards = history.map(_adapter.toDiscardRecord).toList();
      if (!mounted) return;
      setState(() {
        _discards = discards;
        _loadingHistory = false;
      });
    } on DepositHistoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _discards = const [];
        _historyFailure = failure;
        _loadingHistory = false;
      });
      if (failure.kind == DepositHistoryFailureKind.sessionInvalid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(widget.onSessionInvalid());
        });
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[deposit_history] Wallet mapping failure: $error');
        debugPrintStack(
          label: '[deposit_history] wallet stack trace',
          stackTrace: stackTrace,
        );
      }
      if (!mounted) return;
      setState(() {
        _discards = const [];
        _historyFailure = DepositHistoryFailure(
          DepositHistoryFailureKind.unknown,
          'Não foi possível carregar os descartes agora.',
          error,
        );
        _loadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return AppPage(
      title: 'Carteira',
      subtitle: 'Suas BinCoins e as validações recebidas do Totem.',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: Column(
        children: [
          _AuthenticatedWalletHero(balance: profile.binCoinsBalance),
          const SizedBox(height: 14),
          const _AuthenticatedBazaarCard(),
          const SizedBox(height: 18),
          _WalletSectionSelector(
            value: _section,
            onChanged: (value) => setState(() => _section = value),
          ),
          const SizedBox(height: 14),
          if (_section == WalletSection.transactions)
            const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Extrato indisponível',
              message:
                  'As movimentações ainda não possuem uma fonte autenticada.',
              icon: Icons.receipt_long_outlined,
            )
          else if (_loadingHistory)
            const BingoDataState(
              kind: BingoDataStateKind.loading,
              title: 'Carregando histórico',
              message: 'Organizando as informações do Totem.',
            )
          else if (_historyFailure != null)
            BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Descartes indisponíveis',
              message: _historyFailure!.message,
              icon: Icons.cloud_off_rounded,
              action: BingoActionButton(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: _loadHistory,
              ),
            )
          else if (_discards.isEmpty)
            const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Nenhum descarte validado',
              message: 'Os descartes confirmados pelo Totem aparecerão aqui.',
              icon: Icons.recycling_outlined,
            )
          else
            for (final discard in _discards)
              _DiscardHistoryTile(discard: discard),
        ],
      ),
    );
  }
}

class _AuthenticatedWalletHero extends StatelessWidget {
  const _AuthenticatedWalletHero({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return PeriodicHighlight(
      colors: [
        AppColors.blue.withValues(alpha: 0.03),
        Colors.white.withValues(alpha: 0.48),
        AppColors.green.withValues(alpha: 0.08),
      ],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFE2FBFF),
              Colors.white,
              AppColors.green.withValues(alpha: 0.13),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.42)),
          boxShadow: [
            BoxShadow(
              color: AppColors.blue.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suas BinCoins',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const BinCoinIcon(size: 38),
              ],
            ),
            const SizedBox(height: 14),
            BinCoinAmount(
              value: balance,
              size: 34,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.navy,
                fontSize: 38,
              ),
            ),
            const SizedBox(height: 12),
            const BadgeLabel(
              label: 'Saldo autenticado',
              color: AppColors.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthenticatedBazaarCard extends StatelessWidget {
  const _AuthenticatedBazaarCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 64,
            child: Image.asset(
              AppAssets.profileAvatarB3n,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BinBazar indisponível',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                const Text(
                  'Recompensas e resgates ainda não estão conectados.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _AuthenticatedMissionsScreen extends StatefulWidget {
  const _AuthenticatedMissionsScreen({
    required this.profile,
    required this.repository,
    required this.onSessionInvalid,
  });

  final AuthenticatedStudentProfile profile;
  final AuthenticatedMissionsRepository repository;
  final Future<void> Function() onSessionInvalid;

  @override
  State<_AuthenticatedMissionsScreen> createState() =>
      _AuthenticatedMissionsScreenState();
}

class _AuthenticatedMissionsScreenState
    extends State<_AuthenticatedMissionsScreen> {
  List<AuthenticatedMission> _missions = const [];
  MissionsFailure? _failure;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMissions());
  }

  Future<void> _loadMissions() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final missions = await widget.repository.loadActiveMissions();
      if (!mounted) return;
      setState(() {
        _missions = missions;
        _loading = false;
      });
    } on MissionsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _missions = const [];
        _failure = failure;
        _loading = false;
      });
      if (failure.kind == MissionsFailureKind.sessionInvalid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(widget.onSessionInvalid());
        });
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[missions] Screen mapping failure: $error');
        debugPrintStack(
          label: '[missions] screen stack trace',
          stackTrace: stackTrace,
        );
      }
      if (!mounted) return;
      setState(() {
        _missions = const [];
        _failure = MissionsFailure(
          MissionsFailureKind.unknown,
          'Não foi possível carregar as missões agora.',
          error,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Missões de restauração',
      subtitle: '${widget.profile.schoolName} · ${widget.profile.className}',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: _buildState(context),
    );
  }

  Widget _buildState(BuildContext context) {
    if (_loading) {
      return const BingoDataState(
        kind: BingoDataStateKind.loading,
        title: 'Carregando missões',
        message: 'Consultando as missões ativas da sua escola.',
      );
    }
    final failure = _failure;
    if (failure != null) {
      return BingoDataState(
        kind: BingoDataStateKind.empty,
        title: _missionsFailureTitle(failure.kind),
        message: failure.message,
        icon: Icons.cloud_off_rounded,
        action: failure.kind == MissionsFailureKind.sessionInvalid
            ? null
            : BingoActionButton(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: _loadMissions,
              ),
      );
    }
    if (_missions.isEmpty) {
      return const BingoDataState(
        kind: BingoDataStateKind.empty,
        title: 'Nenhuma missão ativa',
        message: 'Novas missões aparecerão aqui quando um ciclo começar.',
        icon: Icons.flag_outlined,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < _missions.length; index++) ...[
          _AuthenticatedMissionCard(mission: _missions[index]),
          if (index != _missions.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AuthenticatedMissionCard extends StatelessWidget {
  const _AuthenticatedMissionCard({required this.mission});

  final AuthenticatedMission mission;

  @override
  Widget build(BuildContext context) {
    final scopeLabel = switch (mission.scope) {
      AuthenticatedMissionScope.student => 'Missão individual',
      AuthenticatedMissionScope.classGroup => 'Missão da turma',
    };
    final stateLabel = mission.isCompleted
        ? 'Concluída'
        : mission.isAchieved
        ? 'Meta atingida'
        : 'Em andamento';
    final stateColor = mission.isCompleted || mission.isAchieved
        ? AppColors.green
        : AppColors.blue;

    return SurfaceCard(
      key: ValueKey('authenticated-mission-${mission.cycleId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mission.definitionTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              BadgeLabel(label: stateLabel, color: stateColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(scopeLabel),
          const SizedBox(height: 10),
          Text(
            '${mission.progress} / ${mission.target}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (mission.rewardBinCoins > 0 || mission.rewardXp > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (mission.rewardBinCoins > 0)
                  BadgeLabel(
                    label: '+${mission.rewardBinCoins} BinCoins',
                    color: AppColors.warning,
                  ),
                if (mission.rewardXp > 0)
                  BadgeLabel(
                    label: '+${mission.rewardXp} XP',
                    color: AppColors.blue,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _missionsFailureTitle(MissionsFailureKind kind) => switch (kind) {
  MissionsFailureKind.sessionInvalid => 'Sessão expirada',
  MissionsFailureKind.network => 'Sem conexão',
  MissionsFailureKind.malformedData => 'Dados de missões inválidos',
  MissionsFailureKind.unknown => 'Missões indisponíveis',
};

class _AuthenticatedRankingScreen extends StatelessWidget {
  const _AuthenticatedRankingScreen({required this.profile});

  final AuthenticatedStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Ranking das turmas',
      subtitle: 'Compare posições e acompanhe a restauração coletiva.',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: Column(
        children: [
          _AuthenticatedRankingHero(profile: profile),
          const SizedBox(height: 18),
          const _AuthenticatedPodiumPlaceholder(),
          const SizedBox(height: 18),
          const ImageHeroCard(
            image: AppAssets.bingopolisMap,
            badge: 'Impacto',
            title: 'Mapa indisponível',
            subtitle:
                'Posições, cenários e impacto aguardam dados e autorização próprios.',
          ),
        ],
      ),
    );
  }
}

class _AuthenticatedRankingHero extends StatelessWidget {
  const _AuthenticatedRankingHero({required this.profile});

  final AuthenticatedStudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.blue.withValues(alpha: 0.08),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppColors.warning,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.className,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text('${profile.classXpBalance} XP da turma'),
                const SizedBox(height: 8),
                const BadgeLabel(label: 'Posição —', color: AppColors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthenticatedPodiumPlaceholder extends StatelessWidget {
  const _AuthenticatedPodiumPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Text(
            'Pódio indisponível',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: _UnavailablePosition(label: 'Turma —')),
              SizedBox(width: 8),
              Expanded(child: _UnavailablePosition(label: 'Turma —')),
              SizedBox(width: 8),
              Expanded(child: _UnavailablePosition(label: 'Turma —')),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnavailablePosition extends StatelessWidget {
  const _UnavailablePosition({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('—'),
        ],
      ),
    );
  }
}

class _UnavailableSurface extends StatelessWidget {
  const _UnavailableSurface({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _profileFailureTitle(ProfileFailureKind kind) {
  return switch (kind) {
    ProfileFailureKind.network => 'Sem conexão com o perfil',
    ProfileFailureKind.sessionInvalid => 'Sessão expirada',
    ProfileFailureKind.authLinkMissing => 'Conta sem vínculo de aluno',
    ProfileFailureKind.notFound => 'Perfil incompleto',
    ProfileFailureKind.malformedData => 'Perfil remoto inválido',
    ProfileFailureKind.unknown => 'Erro ao carregar perfil',
  };
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.firstName,
    required this.onOpenTab,
    super.key,
  });

  final String firstName;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    const scenario = _HomeScenarioOverview();
    const prompt = B1nDialogueStrip(
      message: 'Separe um eletrônico sem uso e confira se ele está seguro.',
      portrait: B1nPortraitVariant.instruction,
    );
    final cta = BingoActionButton(
      label: 'Ver preparo para o Totem',
      tone: BingoActionTone.green,
      icon: Icons.directions_walk,
      onPressed: () =>
          _push(context, const TotemTrackingScreen(mission: activeMission)),
    );
    final primaryFlow = usesLargeText
        ? <Widget>[
            cta,
            const SizedBox(height: 8),
            prompt,
            const SizedBox(height: 8),
            scenario,
          ]
        : <Widget>[
            scenario,
            const SizedBox(height: 8),
            prompt,
            const SizedBox(height: 8),
            cta,
          ];

    return AppPage(
      title: 'Olá, $firstName!',
      subtitle: 'Sua turma está restaurando a ${currentScenario.name}.',
      showBackButton: false,
      child: Column(
        children: [
          ...primaryFlow,
          const SizedBox(height: 18),
          _SoftAction(
            label: 'Alerta SCR4P',
            icon: Icons.warning_amber_rounded,
            onTap: () => _push(context, const Scr4pInfoScreen()),
          ),
          _SoftAction(
            label: 'Ver impacto da turma',
            icon: Icons.auto_graph,
            onTap: () => _push(context, const ImpactScreen()),
          ),
          BingoActionButton(
            onPressed: () => _push(context, const HowItWorksScreen()),
            icon: Icons.info_outline,
            label: 'Como funciona o BinGo',
            style: BingoActionStyle.quiet,
          ),
        ],
      ),
    );
  }
}

class MissionDetailScreen extends StatelessWidget {
  const MissionDetailScreen({required this.mission, super.key});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Missão',
      subtitle: 'Veja a meta, prepare com segurança e acompanhe o progresso.',
      child: Column(
        children: [
          _MissionHero(mission: mission),
          const SizedBox(height: 18),
          _MissionObjective(mission: mission),
          if (mission.state == MissionState.event) ...[
            const SizedBox(height: 14),
            const _MissionEventStatus(),
          ],
          const SizedBox(height: 14),
          B1nDialogueStrip(
            message: mission.detailText,
            tone: mission.state == MissionState.event
                ? AppColors.blue
                : mission.color,
            portrait: mission.state == MissionState.event
                ? B1nPortraitVariant.question
                : B1nPortraitVariant.instruction,
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Caminho da missão',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 14),
          _MissionTimeline(mission: mission),
          const SizedBox(height: 8),
          const _SafetyAlert(
            icon: Icons.health_and_safety_outlined,
            title: 'Segurança antes da recompensa',
            message:
                'Use somente item sem uso e autorizado. Se houver bateria ou dano, peça ajuda a um adulto.',
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

class TotemTrackingScreen extends StatelessWidget {
  const TotemTrackingScreen({required this.mission, super.key});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'No Totem',
      subtitle: 'O Totem valida o descarte. O app mostra o resultado.',
      child: Column(
        children: [
          _TotemHero(mission: mission),
          const SizedBox(height: 18),
          const B1nDialogueStrip(
            message: 'No Totem, eu vou guiar você em cada etapa.',
            portrait: B1nPortraitVariant.celebration,
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Etapas no Totem',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 14),
          const _TotemProcess(),
          const SizedBox(height: 8),
          const _ResponsibilityNotice(),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Antes de levar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          const _TotemSafetyGuide(),
          const SizedBox(height: 18),
          const _TotemResultSummary(),
        ],
      ),
    );
  }
}

enum WalletSection { transactions, discards }

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    this.transactions = binCoinTransactions,
    this.discards = discardHistory,
    this.isLoading = false,
    this.controller,
    super.key,
  });

  final List<BinCoinTransaction> transactions;
  final List<DiscardRecord> discards;
  final bool isLoading;
  final SessionWalletController? controller;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletSection _section = WalletSection.transactions;
  late final SessionWalletController _controller =
      widget.controller ??
      SessionWalletController(initialTransactions: widget.transactions);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final balance = _controller.balance;
        final redeemableRewards = rewards
            .where((reward) => reward.isAvailable(balance))
            .length;
        final transactions = widget.controller == null
            ? widget.transactions
            : _controller.transactions;
        return AppPage(
          title: 'Carteira',
          subtitle: 'Suas BinCoins e as validações recebidas do Totem.',
          showBackButton: false,
          child: Column(
            children: [
              _WalletBalanceHero(
                balance: balance,
                redeemableRewards: redeemableRewards,
              ),
              const SizedBox(height: 14),
              _BazaarAccessCard(
                balance: balance,
                onTap: () =>
                    _push(context, RewardsScreen(controller: _controller)),
              ),
              const SizedBox(height: 18),
              _WalletSectionSelector(
                value: _section,
                onChanged: (value) => setState(() => _section = value),
              ),
              const SizedBox(height: 14),
              if (widget.isLoading)
                const BingoDataState(
                  kind: BingoDataStateKind.loading,
                  title: 'Carregando histórico',
                  message: 'Organizando as informações do Totem.',
                )
              else if (_section == WalletSection.transactions)
                if (transactions.isEmpty)
                  const BingoDataState(
                    kind: BingoDataStateKind.empty,
                    title: 'Nenhuma movimentação',
                    message:
                        'Seus BinCoins aparecerão após uma validação no Totem.',
                    icon: Icons.account_balance_wallet_outlined,
                  )
                else
                  for (final transaction in transactions)
                    _HistoryTile(transaction: transaction)
              else if (widget.discards.isEmpty)
                const BingoDataState(
                  kind: BingoDataStateKind.empty,
                  title: 'Nenhum descarte validado',
                  message:
                      'Os descartes confirmados pelo Totem aparecerão aqui.',
                  icon: Icons.recycling_outlined,
                )
              else
                for (final discard in widget.discards)
                  _DiscardHistoryTile(discard: discard),
            ],
          ),
        );
      },
    );
  }
}

class _WalletBalanceHero extends StatelessWidget {
  const _WalletBalanceHero({
    required this.balance,
    required this.redeemableRewards,
  });

  final int balance;
  final int redeemableRewards;

  @override
  Widget build(BuildContext context) {
    final lockedRewards = rewards
        .where((reward) => !reward.isAvailable(balance))
        .toList();
    final nextReward = lockedRewards.isEmpty ? null : lockedRewards.first;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      container: true,
      label: '$balance BinCoins. $redeemableRewards recompensas disponíveis.',
      child: ExcludeSemantics(
        child: PeriodicHighlight(
          colors: [
            AppColors.blue.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.48),
            AppColors.green.withValues(alpha: 0.08),
          ],
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFE2FBFF),
                  Colors.white,
                  AppColors.green.withValues(alpha: 0.13),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Suas BinCoins',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.34),
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TweenAnimationBuilder<int>(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 700),
                  tween: IntTween(begin: 0, end: balance),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => BinCoinAmount(
                    value: value,
                    size: 34,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.navy,
                      fontSize: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '$redeemableRewards opções disponíveis na simulação',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: AppColors.navy),
                      ),
                    ),
                  ],
                ),
                if (nextReward != null) ...[
                  const SizedBox(height: 14),
                  AnimatedProgressPill(
                    value: balance / nextReward.cost,
                    color: AppColors.green,
                    backgroundColor: AppColors.blue.withValues(alpha: 0.14),
                    height: 8,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Faltam ${nextReward.cost - balance} BinCoins para ${nextReward.title}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BazaarAccessCard extends StatelessWidget {
  const _BazaarAccessCard({required this.balance, required this.onTap});

  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = rewards.where((item) => item.isAvailable(balance)).length;
    return Semantics(
      button: true,
      label: 'Abrir BinBazar. $available recompensas disponíveis.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: [Colors.white, const Color(0xFFE8FBF7)],
              ),
              border: Border.all(
                color: AppColors.green.withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  height: 64,
                  child: Image.asset(
                    AppAssets.profileAvatarB3n,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Abrir BinBazar',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tio B3N separou $available opções para você',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletSectionSelector extends StatelessWidget {
  const _WalletSectionSelector({required this.value, required this.onChanged});

  final WalletSection value;
  final ValueChanged<WalletSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: AppMotion.standard);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _WalletSectionTab(
                key: const ValueKey('wallet-tab-extrato'),
                label: 'Extrato',
                icon: Icons.swap_vert_rounded,
                activeColor: AppColors.green,
                selected: value == WalletSection.transactions,
                duration: duration,
                onTap: () => onChanged(WalletSection.transactions),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WalletSectionTab(
                key: const ValueKey('wallet-tab-descartes'),
                label: 'Descartes',
                icon: Icons.recycling_rounded,
                activeColor: AppColors.blue,
                selected: value == WalletSection.discards,
                duration: duration,
                onTap: () => onChanged(WalletSection.discards),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSectionTab extends StatelessWidget {
  const _WalletSectionTab({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.selected,
    required this.duration,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            height: 46,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? activeColor : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({this.items = rewards, this.controller, super.key});

  final List<RewardItem> items;
  final SessionWalletController? controller;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late final SessionWalletController _controller =
      widget.controller ?? SessionWalletController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => AppPage(
        title: 'BinBazar',
        subtitle: 'Simulação de resgate com BinCoins desta sessão.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BazaarHero(balance: _controller.balance),
            if (_controller.redemptions.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LatestRedemptionCard(redemption: _controller.redemptions.first),
            ],
            const SizedBox(height: 22),
            if (widget.items.isEmpty)
              const BingoDataState(
                kind: BingoDataStateKind.empty,
                title: 'Nenhuma opção disponível',
                message:
                    'Novas recompensas aparecerão quando a escola atualizar.',
                icon: Icons.storefront_outlined,
              )
            else ...[
              Text(
                'Explore as recompensas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final largeText =
                      MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                  final columns = largeText ? 1 : 2;
                  return GridView.builder(
                    key: const ValueKey('binbazar-reward-grid'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: largeText ? 372 : 308,
                    ),
                    itemBuilder: (context, index) {
                      final reward = widget.items[index];
                      return _RewardTile(
                        reward: reward,
                        balance: _controller.balance,
                        onTap: () =>
                            _showRewardDetails(context, reward, _controller),
                      );
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({this.items = missions, super.key});

  final List<Mission> items;

  @override
  Widget build(BuildContext context) {
    final eventItems = items
        .where((mission) => mission.state == MissionState.event)
        .toList();
    final compactItems = items
        .where(
          (mission) =>
              mission.state == MissionState.completed ||
              mission.state == MissionState.upcoming,
        )
        .toList();

    return AppPage(
      title: 'Missões de restauração',
      subtitle: 'Acompanhe metas seguras e o progresso da sua turma.',
      showBackButton: false,
      child: items.isEmpty
          ? const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Nenhuma missão ativa',
              message:
                  'As próximas missões aparecerão quando uma nova jornada começar.',
              icon: Icons.verified_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MissionFeaturedHero(
                  mission: activeMission,
                  onTap: () => _push(
                    context,
                    MissionDetailScreen(mission: activeMission),
                  ),
                ),
                if (eventItems.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Força-tarefa em destaque',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final mission in eventItems) ...[
                    _MissionEventBanner(
                      mission: mission,
                      onTap: () =>
                          _push(context, MissionDetailScreen(mission: mission)),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (compactItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Outras etapas da jornada',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final mission in compactItems) ...[
                    _MissionCompactTile(
                      mission: mission,
                      onTap: () =>
                          _push(context, MissionDetailScreen(mission: mission)),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}

class Scr4pInfoScreen extends StatelessWidget {
  const Scr4pInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Quem é SCR4P?',
      subtitle: 'A corrupção que cresce com o descarte inadequado.',
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneCorruptScr4p,
            badge: 'Alerta ativo',
            title: 'Corrupção eletrônica',
            subtitle: 'Eletrônicos no lixo comum aumentam a corrupção.',
            height: 188,
            alignment: Alignment.centerRight,
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            color: AppColors.scr4p.withValues(alpha: 0.08),
            child: Row(
              children: [
                Image.asset(AppAssets.scr4pPose, height: 82, width: 82),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'SCR4P representa a corrupção causada pelo descarte inadequado. Cada validação segura ajuda sua turma a recuperar BinGópolis.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                _StepRow(
                  number: '1',
                  title: 'A corrupção ocupa cenários',
                  text:
                      'Praças, parques e escolas podem ficar sob a névoa de SCR4P.',
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '2',
                  title: 'A turma recupera setores',
                  text: 'Cada descarte seguro e validado reduz a corrupção.',
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '3',
                  title: 'Participação que conta',
                  text:
                      'Eventos reconhecem a participação elegível e o avanço coletivo.',
                  color: AppColors.scr4p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          BingoActionButton(
            label: 'Ver força-tarefa ativa',
            tone: BingoActionTone.purple,
            icon: Icons.shield,
            onPressed: () => _push(
              context,
              MissionDetailScreen(
                mission: missions.firstWhere(
                  (mission) => mission.state == MissionState.event,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RankingScreen extends StatelessWidget {
  const RankingScreen({this.rows = classRows, this.isPilot = false, super.key});

  final List<(String, String, String, String)> rows;
  final bool isPilot;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Ranking das turmas',
      subtitle: 'Compare posições e acompanhe a restauração coletiva.',
      showBackButton: false,
      child: rows.isEmpty
          ? const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Ranking ainda sem resultados',
              message:
                  'As posições aparecerão após as primeiras validações do ciclo.',
              icon: Icons.emoji_events_outlined,
            )
          : Column(
              children: [
                const _RankingHero(),
                const SizedBox(height: 18),
                const _PodiumCard(),
                const SizedBox(height: 18),
                _ScenarioAccessCard(
                  onPressed: () => _push(
                    context,
                    CityMapScreen(
                      isPilot: isPilot,
                      onOpenScenario: (scenario, visualProgress) => _push(
                        context,
                        CurrentScenarioScreen(
                          scenario: scenario,
                          progress: visualProgress,
                          isPilotSimulation:
                              visualProgress != scenario.progress,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class CurrentScenarioScreen extends StatelessWidget {
  const CurrentScenarioScreen({
    this.scenario = centralSquareScenario,
    this.progress = centralSquareProgress,
    this.isPilotSimulation = false,
    super.key,
  });

  final CityScenario scenario;
  final double progress;
  final bool isPilotSimulation;

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return AppPage(
      title: scenario.name,
      subtitle: progress > 0
          ? 'Acompanhe a restauração construída pela sua turma.'
          : 'Um novo setor da jornada de BinGópolis.',
      child: Column(
        children: [
          B1nDialogueStrip(
            message: progress > 0
                ? 'Cada descarte validado ajuda a tempestade a recuar.'
                : 'Este setor ainda está sob corrupção. A próxima etapa começa aqui.',
            portrait: B1nPortraitVariant.celebration,
          ),
          const SizedBox(height: 18),
          ImageHeroCard(
            image: scenario.assetFor(progress),
            badge: scenario.name,
            title: progress > 0
                ? '${(progress * 100).round()}% restaurada'
                : 'Sob corrupção',
            subtitle: progress > 0
                ? 'Cada validação ajuda a transformar este lugar.'
                : scenario.unlockRequirement,
            height: usesLargeText ? 384 : 220,
            progress: progress,
            progressColor: progress > 0 ? AppColors.green : AppColors.scr4p,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ScenarioMetric(
                  icon: scenario.id == centralSquareScenario.id
                      ? Icons.recycling_rounded
                      : Icons.route_rounded,
                  value: scenario.id == centralSquareScenario.id
                      ? '${currentScenario.nextSectorDiscards}'
                      : '${scenario.order}/3',
                  label: scenario.id == centralSquareScenario.id
                      ? 'descartes para avançar'
                      : 'setor da jornada',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScenarioMetric(
                  icon: scenario.id == centralSquareScenario.id
                      ? Icons.schedule_rounded
                      : Icons.science_outlined,
                  value: scenario.id == centralSquareScenario.id
                      ? '${currentScenario.cycleDays}'
                      : isPilotSimulation
                      ? 'Visual'
                      : '${(scenario.progress * 100).round()}%',
                  label: scenario.id == centralSquareScenario.id
                      ? 'dias neste ciclo'
                      : isPilotSimulation
                      ? 'simulação do mapa'
                      : 'impacto registrado',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _RestorationScale(progress: progress),
          const SizedBox(height: 18),
          SurfaceCard(
            child: Column(
              children: [
                _ScenarioInfoLine(
                  icon: scenario.landmarkIcon,
                  title: 'Área ${scenario.order} da jornada',
                  text: scenario.description,
                  color: AppColors.scr4p,
                ),
                Divider(height: 24, color: AppColors.line),
                _ScenarioInfoLine(
                  icon: Icons.grid_view_rounded,
                  title: 'Como restaurar',
                  text: 'Descartes seguros e validados reduzem a corrupção.',
                  color: AppColors.blue,
                ),
                Divider(height: 24, color: AppColors.line),
                _ScenarioInfoLine(
                  icon: Icons.restart_alt_rounded,
                  title: 'Ciclo',
                  text:
                      'Ao final, os pontos reiniciam e as recompensas do ciclo mudam.',
                  color: AppColors.warning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          BingoActionButton(
            label: 'Ver impacto da turma',
            icon: Icons.auto_graph_rounded,
            tone: BingoActionTone.green,
            onPressed: () => _push(
              context,
              ImpactScreen(
                scenario: scenario,
                registeredProgress: scenario.progress,
                visualProgress: progress,
                isPilotSimulation: isPilotSimulation,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImpactScreen extends StatelessWidget {
  const ImpactScreen({
    this.scenario = centralSquareScenario,
    this.registeredProgress = centralSquareProgress,
    this.visualProgress = centralSquareProgress,
    this.isPilotSimulation = false,
    super.key,
  });

  final CityScenario scenario;
  final double registeredProgress;
  final double visualProgress;
  final bool isPilotSimulation;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Impacto',
      subtitle: 'Veja o resultado registrado da turma em ${scenario.name}.',
      child: Column(
        children: [
          if (registeredProgress > 0)
            ImpactComparison(
              beforeImage: scenario.corruptAsset,
              nowImage: scenario.assetFor(registeredProgress),
              beforeLabel: 'Antes',
              nowLabel: 'Agora',
              beforeFit: BoxFit.cover,
              nowFit: BoxFit.cover,
            )
          else
            ImageHeroCard(
              image: scenario.corruptAsset,
              badge: scenario.name,
              title: 'Restauração ainda não iniciada',
              subtitle: scenario.impact.nextGoal,
              height: 220,
              progress: 0,
              progressColor: AppColors.scr4p,
            ),
          if (isPilotSimulation && visualProgress != registeredProgress) ...[
            const SizedBox(height: 14),
            _PilotSimulationNotice(
              visualProgress: visualProgress,
              registeredProgress: registeredProgress,
            ),
          ],
          const SizedBox(height: 18),
          _ImpactHeadline(scenario: scenario, progress: registeredProgress),
          const SizedBox(height: 18),
          _ImpactMetricsGrid(snapshot: scenario.impact),
          const SizedBox(height: 18),
          _NextTransformationCard(
            scenario: scenario,
            progress: registeredProgress,
          ),
        ],
      ),
    );
  }
}

class _PilotSimulationNotice extends StatelessWidget {
  const _PilotSimulationNotice({
    required this.visualProgress,
    required this.registeredProgress,
  });

  final double visualProgress;
  final double registeredProgress;

  @override
  Widget build(BuildContext context) {
    return _SafetyAlert(
      icon: Icons.visibility_outlined,
      title: 'Simulação visual',
      message:
          'O mapa mostrou ${(visualProgress * 100).round()}%, mas o impacto registrado continua em ${(registeredProgress * 100).round()}%.',
      color: AppColors.blue,
    );
  }
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lines,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: [
          SurfaceCard(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.blue.withValues(alpha: 0.12),
                  child: Icon(icon, color: AppColors.blue, size: 30),
                ),
                const SizedBox(height: 18),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Text(
                          line.$1,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        BadgeLabel(label: line.$2),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Como funciona',
      subtitle: 'Separe com segurança, valide no Totem e acompanhe no app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HowItWorksHero(),
          const SizedBox(height: 22),
          Text(
            'Do descarte ao resultado',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          const _HowItWorksPath(),
          const SizedBox(height: 12),
          Text(
            'O que aparece no app',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const _HowItWorksOutcomes(),
          const SizedBox(height: 14),
          const _SafetyAlert(
            icon: Icons.health_and_safety_outlined,
            title: 'Segurança primeiro',
            message:
                'Não toque em bateria inchada nem em item quente, molhado ou quebrado. Peça ajuda a um adulto.',
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

class _BazaarHero extends StatelessWidget {
  const _BazaarHero({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Balcão do Tio B3N. Você tem $balance BinCoins.',
      child: ExcludeSemantics(
        child: Container(
          height: 224,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.34)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  AppAssets.b3nBazaarCounterScene,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 182,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.42),
                    ),
                  ),
                  child: BinCoinAmount(
                    value: balance,
                    size: 19,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    'Tio B3N cuida do balcão',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showRewardDetails(
  BuildContext context,
  RewardItem reward,
  SessionWalletController controller,
) async {
  final available = reward.isAvailable(controller.balance);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 150,
                height: 128,
                child: BingoAssetImage(
                  asset: reward.asset,
                  fit: BoxFit.contain,
                  semanticLabel: reward.title,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(reward.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(reward.description),
            const SizedBox(height: 14),
            _RewardPriceBand(
              value: reward.cost,
              color: reward.color,
              large: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: Text('Seu saldo: ${controller.balance} BinCoins'),
            ),
            const SizedBox(height: 12),
            _SafetyAlert(
              icon: available
                  ? Icons.storefront_outlined
                  : Icons.lock_outline_rounded,
              title: reward.statusFor(controller.balance),
              message: available
                  ? reward.pickupInstruction
                  : 'Faltam ${reward.cost - controller.balance} BinCoins nesta simulação.',
              color: available ? AppColors.green : AppColors.blue,
            ),
            const SizedBox(height: 16),
            BingoActionButton(
              label: 'Simular por ${reward.cost} BinCoins',
              icon: Icons.redeem_rounded,
              tone: BingoActionTone.green,
              onPressed: available
                  ? () => Navigator.of(context).pop(true)
                  : null,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final redemption = controller.redeem(reward);
  if (redemption == null) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFDFF8E6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.green,
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Simulação concluída',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${reward.title} foi registrado no Extrato desta simulação.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _PickupCode(code: redemption.pickupCode),
            const SizedBox(height: 12),
            Text(reward.pickupInstruction, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _PickupCode extends StatelessWidget {
  const _PickupCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Código demonstrativo de retirada $code',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.32)),
        ),
        child: Column(
          children: [
            Text(
              'Código demonstrativo de retirada',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 5),
            Text(
              code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.blue,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestRedemptionCard extends StatelessWidget {
  const _LatestRedemptionCard({required this.redemption});

  final RewardRedemption redemption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_rounded, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Última simulação',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  redemption.rewardTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Text(
            redemption.pickupCode,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.blue),
          ),
        ],
      ),
    );
  }
}

class _RewardPriceBand extends StatelessWidget {
  const _RewardPriceBand({
    required this.value,
    required this.color,
    this.large = false,
  });

  final int value;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
        key: ValueKey('reward-price-$value'),
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: BinCoinAmount(
            value: value,
            size: large ? 25 : 23,
            style:
                (large
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
          ),
        ),
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.reward,
    required this.balance,
    required this.onTap,
  });

  final RewardItem reward;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = reward.isAvailable(balance);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      button: true,
      label:
          '${reward.title}, ${reward.cost} BinCoins, ${reward.statusFor(balance)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            key: ValueKey('reward-card-${reward.id}'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: reward.color.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: largeText ? 104 : 96,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: reward.color.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: BingoAssetImage(
                          asset: reward.asset,
                          fit: BoxFit.contain,
                          semanticLabel: reward.title,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(
                          available
                              ? Icons.check_circle_rounded
                              : Icons.lock_outline_rounded,
                          color: available
                              ? AppColors.green
                              : AppColors.textMuted,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: largeText ? 70 : 44,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      reward.title,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _RewardPriceBand(
                  value: reward.cost,
                  color: reward.color,
                  large: largeText,
                ),
                const SizedBox(height: 7),
                SizedBox(
                  height: 10,
                  child: available
                      ? null
                      : Align(
                          alignment: Alignment.topCenter,
                          child: AnimatedProgressPill(
                            value: balance / reward.cost,
                            color: reward.color,
                            height: 7,
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Container(
                  key: ValueKey('reward-action-${reward.id}'),
                  width: double.infinity,
                  height: largeText ? 52 : 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: available
                        ? AppColors.green
                        : reward.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: available
                          ? AppColors.green
                          : reward.color.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        available
                            ? Icons.redeem_rounded
                            : Icons.lock_outline_rounded,
                        color: available ? Colors.white : AppColors.textMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          available
                              ? 'Simular resgate'
                              : 'Faltam ${reward.cost - balance}',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: available
                                    ? Colors.white
                                    : AppColors.textMuted,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HowItWorksHero extends StatelessWidget {
  const _HowItWorksHero();

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      container: true,
      label:
          'Do descarte ao impacto. O Totem valida o item e o app mostra o resultado.',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: usesLargeText ? 430 : 310,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    AppAssets.howItWorksScene,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.navy.withValues(alpha: 0.10),
                          AppColors.navy.withValues(alpha: 0.96),
                        ],
                        stops: const [0, 0.54, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BadgeLabel(
                        label: 'Totem + app',
                        color: AppColors.blue,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Do descarte ao impacto',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'O app orienta, o Totem valida e a cadeia responsável encaminha o item.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HowItWorksPath extends StatelessWidget {
  const _HowItWorksPath();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _HowItWorksStep(
          number: 1,
          icon: Icons.inventory_2_outlined,
          title: 'Prepare com segurança',
          text: 'Separe um eletrônico sem uso, seco, seguro e autorizado.',
          color: AppColors.green,
        ),
        _HowItWorksStep(
          number: 2,
          icon: Icons.precision_manufacturing_outlined,
          title: 'Use o Totem',
          text: 'Identifique sua turma e siga uma etapa por vez na tela.',
          color: AppColors.blue,
        ),
        _HowItWorksStep(
          number: 3,
          icon: Icons.phone_android_outlined,
          title: 'Acompanhe no app',
          text:
              'Depois da validação, consulte BinCoins, pontos e progresso territorial.',
          color: AppColors.warning,
          isLast: true,
        ),
      ],
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    this.isLast = false,
  });

  final int number;
  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Etapa $number de 3. $title. $text',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  if (!isLast)
                    Container(
                      width: 3,
                      height: 58,
                      color: color.withValues(alpha: 0.24),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 8 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. $title',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(text),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksOutcomes extends StatelessWidget {
  const _HowItWorksOutcomes();

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = <Widget>[
          const Expanded(
            child: _HowItWorksOutcome(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Resultado pessoal',
              text: 'BinCoins entram na sua Carteira pessoal.',
              color: AppColors.blue,
            ),
          ),
          const Expanded(
            child: _HowItWorksOutcome(
              icon: Icons.groups_2_outlined,
              title: 'Resultado coletivo',
              text: 'Pontos mostram o avanço coletivo da turma.',
              color: AppColors.green,
            ),
          ),
        ];

        if (usesLargeText || constraints.maxWidth < 340) {
          return const Column(
            children: [
              _HowItWorksOutcome(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Resultado pessoal',
                text: 'BinCoins entram na sua Carteira pessoal.',
                color: AppColors.blue,
              ),
              SizedBox(height: 10),
              _HowItWorksOutcome(
                icon: Icons.groups_2_outlined,
                title: 'Resultado coletivo',
                text: 'Pontos mostram o avanço coletivo da turma.',
                color: AppColors.green,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [cards[0], const SizedBox(width: 10), cards[1]],
        );
      },
    );
  }
}

class _HowItWorksOutcome extends StatelessWidget {
  const _HowItWorksOutcome({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }
}

class _MissionFeaturedHero extends StatelessWidget {
  const _MissionFeaturedHero({required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final compactWidth = MediaQuery.sizeOf(context).width < 380;
    return Semantics(
      button: true,
      label:
          'Missão ativa. ${mission.title}. ${mission.subtitle}. '
          'Recompensa ${mission.reward}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: AppColors.deepCyan,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: usesLargeText
                  ? 520
                  : compactWidth
                  ? 286
                  : 248,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      mission.image,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                  Positioned(
                    right: usesLargeText ? -20 : 4,
                    bottom: -5,
                    width: usesLargeText ? 148 : 140,
                    height: usesLargeText ? 188 : 178,
                    child: Image.asset(
                      AppAssets.b1nMissionReady,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppColors.deepCyan.withValues(alpha: 0.96),
                            AppColors.deepCyan.withValues(alpha: 0.68),
                            AppColors.deepCyan.withValues(alpha: 0.04),
                          ],
                          stops: const [0, 0.52, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BadgeLabel(
                            label: 'Em andamento',
                            color: AppColors.green,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: usesLargeText ? double.infinity : 225,
                            child: Text(
                              mission.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          SizedBox(
                            width: usesLargeText ? double.infinity : 235,
                            child: Text(
                              mission.subtitle,
                              maxLines: usesLargeText ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.90),
                                  ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: usesLargeText ? double.infinity : 230,
                            child: AnimatedProgressPill(
                              value: mission.progress,
                              color: AppColors.green,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.32,
                              ),
                              height: 10,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MissionRewardBadge(mission: mission),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionEventBanner extends StatelessWidget {
  const _MissionEventBanner({required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final compactWidth = MediaQuery.sizeOf(context).width < 380;
    final stackedFooter = largeText || compactWidth;
    return Semantics(
      button: true,
      label:
          'Evento. ${mission.title}. ${mission.subtitle}. '
          'Recompensa ${mission.reward}.',
      child: Material(
        color: const Color(0xFFFCF9FF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: largeText
                ? compactWidth
                      ? 500
                      : 460
                : compactWidth
                ? 268
                : 216,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: mission.color.withValues(alpha: 0.30)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  mission.color.withValues(alpha: 0.10),
                  mission.color.withValues(alpha: 0.18),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: largeText ? 2 : 6,
                  bottom: 0,
                  width: largeText ? 94 : 116,
                  height: largeText ? 182 : 166,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          mission.color.withValues(alpha: 0.28),
                          mission.color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: BingoAssetImage(
                      asset: AppAssets.scr4pDefense,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      filterQuality: FilterQuality.high,
                      semanticLabel: 'SCR4P em postura defensiva',
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          14,
                          stackedFooter ? 84 : 132,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AÇÃO COLETIVA',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: mission.color,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mission.title,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              mission.subtitle,
                              maxLines: stackedFooter ? 3 : 2,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          0,
                          stackedFooter ? 84 : 132,
                          14,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            AnimatedProgressPill(
                              value: mission.progress,
                              color: mission.color,
                              height: 9,
                            ),
                            const SizedBox(height: 8),
                            if (stackedFooter)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mission.reward,
                                    maxLines: 3,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: mission.color,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Ver evento',
                                          maxLines: 2,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: mission.color,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: mission.color,
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      mission.reward,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: mission.color,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    'Ver evento',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: mission.color,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: mission.color,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionCompactTile extends StatelessWidget {
  const _MissionCompactTile({required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCompleted = mission.state == MissionState.completed;
    final tone = isCompleted ? AppColors.green : AppColors.blue;
    final stateLabel = isCompleted ? 'Missão concluída' : 'Próxima missão';

    return Semantics(
      button: true,
      label:
          '$stateLabel. ${mission.title}. ${mission.subtitle}. '
          'Recompensa ${mission.reward}.',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_rounded
                        : Icons.lock_clock_outlined,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stateLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mission.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(mission.subtitle),
                      const SizedBox(height: 7),
                      Text(
                        mission.reward,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionEventStatus extends StatelessWidget {
  const _MissionEventStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.scr4p.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.scr4p.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.scr4p.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.scr4p,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A corrupção ainda ocupa 58% do setor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const AnimatedProgressPill(
            value: 0.58,
            color: AppColors.scr4p,
            height: 10,
          ),
          const SizedBox(height: 8),
          const Text(
            'Faltam 3 descartes validados para concluir a meta coletiva.',
          ),
        ],
      ),
    );
  }
}

class _RankingHero extends StatelessWidget {
  const _RankingHero();

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      container: true,
      label:
          'Sua turma, 9ºA, está em quarto lugar com 76000 pontos. '
          'A próxima meta é alcançar o top 3 com mais 5000 pontos.',
      child: ExcludeSemantics(
        child: SurfaceCard(
          color: const Color(0xFFEAF6FF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (usesLargeText) ...[
                const BadgeLabel(label: '4º lugar', color: AppColors.warning),
                const SizedBox(height: 10),
                const _RankingScore(),
              ] else
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _RankingScore()),
                    SizedBox(width: 12),
                    BadgeLabel(label: '4º lugar', color: AppColors.warning),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    color: AppColors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Próxima meta: 5000 pontos para o top 3',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const AnimatedProgressPill(
                value: 76000 / 81000,
                color: AppColors.green,
                backgroundColor: Colors.white,
                height: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankingScore extends StatelessWidget {
  const _RankingScore();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sua turma · 9ºA', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '76.000 pts',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard();

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.emoji_events, color: AppColors.warning),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Turmas da Praça',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );

    return SurfaceCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (usesLargeText) ...[
            title,
            const SizedBox(height: 10),
            const _RankingCycleBadge(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                const _RankingCycleBadge(),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            'O top 3 e a participação elegível recebem bônus no fim do ciclo.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                child: _PodiumPlace(
                  position: '2º',
                  room: '8ºB',
                  points: '92.000 pts',
                  height: 86,
                  color: AppColors.blue,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PodiumPlace(
                  position: '1º',
                  room: '7ºA',
                  points: '124.000 pts',
                  height: 112,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PodiumPlace(
                  position: '3º',
                  room: '6ºC',
                  points: '81.000 pts',
                  height: 72,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankingCycleBadge extends StatelessWidget {
  const _RankingCycleBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${currentScenario.cycleDays} dias no ciclo atual',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.42),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 17,
                color: AppColors.navy,
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${currentScenario.cycleDays} dias',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'no ciclo',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({
    required this.position,
    required this.room,
    required this.points,
    required this.height,
    required this.color,
  });

  final String position;
  final String room;
  final String points;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$position lugar, turma $room, $points',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Icon(Icons.workspace_premium_rounded, color: color, size: 30),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                position,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: height,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.48)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(room, style: Theme.of(context).textTheme.titleMedium),
                    Text(points, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioAccessCard extends StatelessWidget {
  const _ScenarioAccessCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 138,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    AppAssets.bingopolisTerrainTile,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    left: -70,
                    top: -68,
                    width: 270,
                    child: Opacity(
                      opacity: 0.62,
                      child: Image.asset(AppAssets.corruptionFogMid),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: -8,
                    width: 118,
                    child: Image.asset(
                      AppAssets.b1nMapGuide,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    left: 14,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE60B234A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.deepCyan),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_rounded,
                            size: 16,
                            color: AppColors.green,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Jornada em expansão',
                            style: TextStyle(
                              fontFamily: 'Sora',
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'A jornada de restauração',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const Icon(
                      Icons.location_city_rounded,
                      color: AppColors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'A ${currentScenario.name} é o começo. Cada descarte validado afasta a névoa e abre novos caminhos.',
                ),
                const SizedBox(height: 12),
                AnimatedProgressPill(
                  value: currentScenario.restoredProgress,
                  color: AppColors.green,
                ),
                const SizedBox(height: 14),
                BingoActionButton(
                  label: 'Explorar BinGópolis',
                  icon: Icons.map_outlined,
                  style: BingoActionStyle.secondary,
                  onPressed: onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioMetric extends StatelessWidget {
  const _ScenarioMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RestorationScale extends StatelessWidget {
  const _RestorationScale({this.progress = centralSquareProgress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: const Color(0xFFF4FAFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, color: AppColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Régua de restauração',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final markerX = (constraints.maxWidth - 18) * progress;
              return SizedBox(
                height: 22,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.scr4p.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: currentScenario.restoredProgress,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: markerX,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.green, width: 4),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('Corrompida')),
              Expanded(
                child: Text('Em recuperação', textAlign: TextAlign.center),
              ),
              Expanded(child: Text('Restaurada', textAlign: TextAlign.end)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScenarioInfoLine extends StatelessWidget {
  const _ScenarioInfoLine({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(text),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImpactHeadline extends StatelessWidget {
  const _ImpactHeadline({required this.scenario, required this.progress});

  final CityScenario scenario;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.blue.withValues(alpha: 0.12),
            Colors.white,
            AppColors.green.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_city_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(progress * 100).round()}% restaurada',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  progress > 0
                      ? 'Sua turma está restaurando ${scenario.name}.'
                      : 'A restauração registrada deste setor ainda não começou.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactMetricsGrid extends StatelessWidget {
  const _ImpactMetricsGrid({required this.snapshot});

  final ScenarioImpactSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.scale_rounded,
              value: _formatImpactWeight(snapshot.recoveredWeightKg),
              label: 'encaminhados corretamente',
              color: AppColors.green,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.recycling_rounded,
              value: '${snapshot.validatedDiscards}',
              label: 'descartes validados',
              color: AppColors.blue,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.groups_2_rounded,
              value: '${snapshot.activeStudents}',
              label: 'alunos ativos',
              color: AppColors.warning,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.flag_rounded,
              value: '${snapshot.remainingDiscards}',
              label: snapshot.validatedDiscards == 0
                  ? 'para a primeira meta'
                  : 'para o próximo setor',
              color: AppColors.scr4p,
            ),
          ],
        );
      },
    );
  }
}

class _ImpactMetric extends StatelessWidget {
  const _ImpactMetric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(label),
        ],
      ),
    );
  }
}

class _NextTransformationCard extends StatelessWidget {
  const _NextTransformationCard({
    required this.scenario,
    required this.progress,
  });

  final CityScenario scenario;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: Image.asset(
                    scenario.id == centralSquareScenario.id
                        ? AppAssets.sceneTransition
                        : scenario.combatAsset,
                    fit: BoxFit.cover,
                  ),
                ),
                const Positioned(
                  left: 14,
                  top: 14,
                  child: BadgeLabel(label: 'Próxima transformação'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress > 0
                      ? 'Um novo setor está perto'
                      : 'A primeira restauração começa aqui',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(scenario.impact.nextGoal),
                const SizedBox(height: 14),
                AnimatedProgressPill(
                  value: progress,
                  color: AppColors.green,
                  backgroundColor: Color(0xFFE8EEF5),
                  height: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatImpactWeight(double value) {
  if (value == 0) return '0 kg';
  return '${value.toStringAsFixed(1).replaceAll('.', ',')} kg';
}

class _MissionHero extends StatelessWidget {
  const _MissionHero({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      container: true,
      label:
          '${mission.detailTitle}. ${mission.title}. Recompensa ${mission.reward}.',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  mission.image,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.navy.withValues(alpha: 0.04),
                        AppColors.navy.withValues(alpha: 0.58),
                        AppColors.navy.withValues(alpha: 0.92),
                      ],
                      stops: const [0, 0.30, 1],
                    ),
                  ),
                ),
              ),
              Container(
                constraints: BoxConstraints(
                  minHeight: usesLargeText ? 280 : 204,
                ),
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BadgeLabel(
                      label: mission.detailTitle,
                      color: mission.color,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mission.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _MissionRewardBadge(mission: mission),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionRewardBadge extends StatelessWidget {
  const _MissionRewardBadge({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mission.reward.contains('BinCoins'))
            const BinCoinIcon(size: 20)
          else
            Icon(Icons.map_outlined, size: 20, color: mission.color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              mission.reward,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionObjective extends StatelessWidget {
  const _MissionObjective({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mission.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: mission.color, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, color: mission.color, size: 23),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Objetivo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(mission.subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionTimeline extends StatelessWidget {
  const _MissionTimeline({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < mission.steps.length; i++)
          _MissionTimelineStep(
            number: i + 1,
            title: mission.steps[i].$1,
            text: mission.steps[i].$2,
            color: mission.color,
            isLast: i == mission.steps.length - 1,
          ),
      ],
    );
  }
}

class _MissionTimelineStep extends StatelessWidget {
  const _MissionTimelineStep({
    required this.number,
    required this.title,
    required this.text,
    required this.color,
    required this.isLast,
  });

  final int number;
  final String title;
  final String text;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 3,
                  height: 52,
                  color: color.withValues(alpha: 0.24),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 14 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotemHero extends StatelessWidget {
  const _TotemHero({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      container: true,
      label:
          'Totem físico do BinGo. Ele valida o descarte da missão ${mission.title}.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFE8F8FF)),
                  ),
                  Positioned.fill(
                    left: 110,
                    child: Transform.scale(
                      scale: 1.25,
                      alignment: Alignment.centerRight,
                      child: Image.asset(
                        AppAssets.totemConceptFull,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFFF7FCFF),
                            const Color(0xFFF7FCFF).withValues(alpha: 0.96),
                            const Color(
                              0xFFF7FCFF,
                            ).withValues(alpha: usesLargeText ? 0.86 : 0.12),
                          ],
                          stops: const [0, 0.50, 0.82],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    constraints: BoxConstraints(
                      minHeight: usesLargeText ? 300 : 222,
                    ),
                    padding: const EdgeInsets.all(18),
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: usesLargeText
                          ? constraints.maxWidth
                          : constraints.maxWidth * 0.60,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BadgeLabel(
                            label: 'Equipamento físico',
                            color: AppColors.blue,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'O Totem valida o descarte',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            mission.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum TotemStepState { ready, current, upcoming }

class _TotemProcess extends StatelessWidget {
  const _TotemProcess();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TotemProcessStep(
          number: 1,
          title: 'Item seguro e autorizado',
          text: 'Eletrônico sem uso, seco, sem dano e autorizado.',
          state: TotemStepState.ready,
        ),
        _TotemProcessStep(
          number: 2,
          title: 'Use o Totem',
          text: 'Identifique sua turma e siga uma orientação por vez.',
          state: TotemStepState.current,
        ),
        _TotemProcessStep(
          number: 3,
          title: 'Resultado no app',
          text: 'Após a validação, BinCoins e pontos aparecem no app.',
          state: TotemStepState.upcoming,
          isLast: true,
        ),
      ],
    );
  }
}

class _TotemProcessStep extends StatelessWidget {
  const _TotemProcessStep({
    required this.number,
    required this.title,
    required this.text,
    required this.state,
    this.isLast = false,
  });

  final int number;
  final String title;
  final String text;
  final TotemStepState state;
  final bool isLast;

  Color get color => switch (state) {
    TotemStepState.ready => AppColors.green,
    TotemStepState.current => AppColors.blue,
    TotemStepState.upcoming => AppColors.warning,
  };

  String get stateLabel => switch (state) {
    TotemStepState.ready => 'Concluído',
    TotemStepState.current => 'Etapa atual',
    TotemStepState.upcoming => 'Próxima etapa',
  };

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == TotemStepState.current;
    return Semantics(
      container: true,
      label: '$stateLabel: $title. $text',
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? color : AppColors.line,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: state == TotemStepState.ready
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 21,
                      )
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stateLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(text),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsibilityNotice extends StatelessWidget {
  const _ResponsibilityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.volunteer_activism_outlined,
            color: AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Use somente item sem uso e autorizado. Nunca compre, quebre ou pegue algo de outra pessoa para pontuar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotemSafetyGuide extends StatelessWidget {
  const _TotemSafetyGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: [
          _TotemSafetyRow(
            icon: Icons.check_circle_outline_rounded,
            title: 'Pode levar',
            text: 'Cabos, mouse, fone e acessórios pequenos, secos e sem dano.',
            color: AppColors.green,
          ),
          Divider(height: 24, color: AppColors.line),
          _TotemSafetyRow(
            icon: Icons.supervisor_account_outlined,
            title: 'Peça ajuda',
            text:
                'Celular, bateria solta, item trincado ou peça com parte exposta.',
            color: AppColors.warning,
          ),
          Divider(height: 24, color: AppColors.line),
          _TotemSafetyRow(
            icon: Icons.dangerous_outlined,
            title: 'Não toque',
            text:
                'Bateria inchada, vazando, molhada ou quente. Chame um adulto.',
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

class _TotemResultSummary extends StatelessWidget {
  const _TotemResultSummary();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Depois da validação, BinCoins aparecem na Carteira. '
          'Pontos e progresso territorial aparecem no Impacto.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8FD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.18)),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Depois da validação',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'O Totem envia a validação e o app atualiza as áreas de consulta.',
              ),
              const SizedBox(height: 12),
              const _TotemResultRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Carteira',
                text: 'BinCoins recebidos',
                color: AppColors.blue,
              ),
              const SizedBox(height: 10),
              const _TotemResultRow(
                icon: Icons.auto_graph_outlined,
                title: 'Impacto',
                text: 'Pontos e progresso territorial',
                color: AppColors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotemResultRow extends StatelessWidget {
  const _TotemResultRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title · ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotemSafetyRow extends StatelessWidget {
  const _TotemSafetyRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 23),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(text),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyAlert extends StatelessWidget {
  const _SafetyAlert({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.transaction});

  final BinCoinTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.kind == TransactionKind.credit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isCredit ? AppColors.green : AppColors.danger)
                    .withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit ? Icons.add_rounded : Icons.remove_rounded,
                color: isCredit ? AppColors.green : AppColors.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(transaction.subtitle),
                ],
              ),
            ),
            BinCoinAmount(
              value: transaction.amount,
              size: 18,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.navy),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscardHistoryTile extends StatelessWidget {
  const _DiscardHistoryTile({required this.discard});

  final DiscardRecord discard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(discard.icon, color: AppColors.blue, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        discard.item,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(discard.dateLabel),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_rounded,
                  size: 20,
                  color: AppColors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BinCoinAmount(
                    value: discard.binCoins,
                    size: 18,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: AppColors.navy),
                  ),
                ),
                const Icon(
                  Icons.groups_2_outlined,
                  size: 18,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 5),
                Text(
                  '+${discard.classPoints} pts turma',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Validado no Totem',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.text,
    this.color = AppColors.blue,
  });

  final String number;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: number,
            child: ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeScenarioOverview extends StatelessWidget {
  const _HomeScenarioOverview();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                SizedBox(
                  height: 92,
                  width: double.infinity,
                  child: Image.asset(
                    AppAssets.sceneClean,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: BadgeLabel(label: currentScenario.name),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${currentScenario.restoredPercent}% restaurada',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                AnimatedProgressPill(value: currentScenario.restoredProgress),
                const SizedBox(height: 10),
                Text(
                  'Em andamento',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.recycling_rounded,
                        color: AppColors.green,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        activeMission.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      color: AppColors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${currentScenario.nextSectorDiscards} descartes '
                        'para o próximo setor',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftAction extends StatelessWidget {
  const _SoftAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: AppColors.blue),
            title: Text(label, style: Theme.of(context).textTheme.titleMedium),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
