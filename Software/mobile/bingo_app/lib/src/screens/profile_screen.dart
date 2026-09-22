import 'package:flutter/material.dart';

import '../auth/auth_gateway.dart';
import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/b1n_guide.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import '../widgets/periodic_highlight.dart';
import 'change_pin_screen.dart';
import 'access_flow_screen.dart';

const _pilotProfileLevel = 3;

class _ProfileAvatarOption {
  const _ProfileAvatarOption({
    required this.id,
    required this.label,
    required this.asset,
    required this.requiredLevel,
  });

  final String id;
  final String label;
  final String asset;
  final int requiredLevel;
}

class _ProfileThemeOption {
  const _ProfileThemeOption({
    required this.id,
    required this.label,
    required this.primary,
    required this.secondary,
    required this.requiredLevel,
  });

  final String id;
  final String label;
  final Color primary;
  final Color secondary;
  final int requiredLevel;
}

const _profileAvatars = <_ProfileAvatarOption>[
  _ProfileAvatarOption(
    id: 'b1n-default',
    label: 'B1N guia',
    asset: AppAssets.b1nPortraitCelebration,
    requiredLevel: 1,
  ),
  _ProfileAvatarOption(
    id: 'b1n-instruction',
    label: 'B1N inventor',
    asset: AppAssets.b1nPortraitInstruction,
    requiredLevel: 2,
  ),
  _ProfileAvatarOption(
    id: 'b1n-question',
    label: 'B1N atento',
    asset: AppAssets.b1nPortraitQuestion,
    requiredLevel: 2,
  ),
  _ProfileAvatarOption(
    id: 'b3n-shopkeeper',
    label: 'Tio B3N',
    asset: AppAssets.profileAvatarB3n,
    requiredLevel: 3,
  ),
  _ProfileAvatarOption(
    id: 'scr4p-defense',
    label: 'SCR4P',
    asset: AppAssets.profileAvatarScr4p,
    requiredLevel: 3,
  ),
  _ProfileAvatarOption(
    id: 'b1n-reward',
    label: 'B1N celebrando',
    asset: AppAssets.profileAvatarB1nReward,
    requiredLevel: 4,
  ),
  _ProfileAvatarOption(
    id: 'b1n-hero',
    label: 'B1N restaurador',
    asset: AppAssets.profileAvatarB1nHero,
    requiredLevel: 5,
  ),
];

const _profileThemes = <_ProfileThemeOption>[
  _ProfileThemeOption(
    id: 'city-blue',
    label: 'Cidade azul',
    primary: AppColors.blue,
    secondary: AppColors.deepCyan,
    requiredLevel: 1,
  ),
  _ProfileThemeOption(
    id: 'eco-green',
    label: 'Eco verde',
    primary: AppColors.green,
    secondary: AppColors.blue,
    requiredLevel: 2,
  ),
  _ProfileThemeOption(
    id: 'restoration-cyan',
    label: 'Restauração',
    primary: Color(0xFF18D7D1),
    secondary: AppColors.green,
    requiredLevel: 3,
  ),
  _ProfileThemeOption(
    id: 'scr4p-purple',
    label: 'Energia SCR4P',
    primary: AppColors.scr4p,
    secondary: AppColors.blue,
    requiredLevel: 3,
  ),
  _ProfileThemeOption(
    id: 'solar-yellow',
    label: 'Energia solar',
    primary: AppColors.warning,
    secondary: AppColors.green,
    requiredLevel: 4,
  ),
  _ProfileThemeOption(
    id: 'hero-navy',
    label: 'Herói da cidade',
    primary: AppColors.deepCyan,
    secondary: AppColors.green,
    requiredLevel: 5,
  ),
];

class _ProfileViewData {
  const _ProfileViewData({
    required this.profile,
    required this.customization,
    required this.store,
  });

  final StudentProfile profile;
  final ProfileCustomization customization;
  final ProfileCustomizationStore store;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.onGoHome,
    this.repository,
    this.onExitPilot,
    super.key,
  }) : authenticatedProfile = null,
       onLogout = null,
       onOpenMissions = null,
       customizationStore = null;

  const ProfileScreen.authenticated({
    required AuthenticatedStudentProfile profile,
    required this.onLogout,
    this.onOpenMissions,
    this.customizationStore,
    super.key,
  }) : authenticatedProfile = profile,
       repository = null,
       onGoHome = null,
       onExitPilot = null;

  final ProfileRepository? repository;
  final VoidCallback? onGoHome;
  final Future<void> Function()? onExitPilot;
  final AuthenticatedStudentProfile? authenticatedProfile;
  final Future<AuthFailure?> Function()? onLogout;
  final VoidCallback? onOpenMissions;
  final ProfileCustomizationStore? customizationStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Future<_ProfileViewData> _data = _loadData();
  ProfileCustomization? _customization;
  ProfileCustomizationStore? _store;
  var _loggingOut = false;
  String? _logoutError;

  Future<_ProfileViewData> _loadData() async {
    final authenticatedProfile = widget.authenticatedProfile;
    if (authenticatedProfile != null) {
      final store =
          widget.customizationStore ??
          await SharedPreferencesCustomizationStore.create(
            studentId: authenticatedProfile.id,
          );
      final customization = await store.loadCustomization();
      _store = store;
      _customization = customization;
      return _ProfileViewData(
        profile: StudentProfile(
          school: authenticatedProfile.schoolName,
          identifier: authenticatedProfile.name,
        ),
        customization: customization,
        store: store,
      );
    }

    final profile =
        await widget.repository?.loadProfile() ??
        const StudentProfile(school: 'ENIAC', identifier: 'Marco Caparra');
    final store = widget.repository is ProfileCustomizationStore
        ? widget.repository! as ProfileCustomizationStore
        : await SharedPreferencesCustomizationStore.create();
    final customization = await store.loadCustomization();
    _store = store;
    _customization = customization;
    return _ProfileViewData(
      profile: profile,
      customization: customization,
      store: store,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedProfile = widget.authenticatedProfile;
    if (authenticatedProfile != null) {
      return FutureBuilder<_ProfileViewData>(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final customization =
              _customization ??
              data?.customization ??
              const ProfileCustomization();
          return _buildAuthenticated(
            context,
            authenticatedProfile,
            customization,
            customizationReady: data != null,
          );
        },
      );
    }
    return FutureBuilder<_ProfileViewData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final profile =
            data?.profile ??
            const StudentProfile(school: 'ENIAC', identifier: 'Marco Caparra');
        final customization =
            _customization ??
            data?.customization ??
            const ProfileCustomization();
        return AppPage(
          title: 'Sua jornada',
          subtitle: 'Progresso, conquistas e conta em um só lugar.',
          showBackButton: false,
          dataStatus: AppDataStatus.local,
          child: Column(
            children: [
              _ProfileHeader(
                profile: profile,
                customization: customization,
                onEdit: data == null
                    ? null
                    : () => _openCustomization(
                        context,
                        customization,
                        currentLevel: _pilotProfileLevel,
                      ),
              ),
              const SizedBox(height: 16),
              const _ResourceSummary(),
              const SizedBox(height: 16),
              const _LevelPath(currentLevel: _pilotProfileLevel),
              const SizedBox(height: 16),
              const B1nGuide(
                asset: AppAssets.b1nReward,
                title: 'Sua jornada está avançando!',
                message: 'Faltam 240 pontos pessoais para chegar a Guardião.',
                tone: AppColors.green,
                compact: true,
                portrait: B1nPortraitVariant.celebration,
              ),
              const SizedBox(height: 14),
              BingoActionButton(
                label: 'Ver missões',
                icon: Icons.arrow_forward_rounded,
                tone: BingoActionTone.green,
                onPressed: widget.onGoHome,
              ),
              const SizedBox(height: 18),
              _AccountPanel(
                profile: profile,
                repository: widget.repository,
                onExitPilot: widget.onExitPilot,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAuthenticated(
    BuildContext context,
    AuthenticatedStudentProfile profile,
    ProfileCustomization customization, {
    required bool customizationReady,
  }) {
    final progress = profile.progress;
    return AppPage(
      title: 'Sua jornada',
      subtitle: 'Dados reais da sua conta vinculada.',
      showBackButton: false,
      dataStatus: AppDataStatus.remote,
      child: Column(
        children: [
          _ProfileHeader(
            profile: StudentProfile(
              school: profile.schoolName,
              identifier: profile.name,
            ),
            className: profile.className,
            customization: customization,
            levelNumber: progress.levelNumber,
            levelName: progress.levelName,
            journeyProgress: progress.progressToNextLevel,
            onEdit: customizationReady
                ? () => _openCustomization(
                    context,
                    customization,
                    currentLevel: progress.levelNumber,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          _ResourceSummary(
            personalPoints: progress.validDepositCount.toString(),
            personalLabel: 'Descartes',
            classPoints: profile.classXpBalance.toString(),
            classLabel: 'XP da turma',
            binCoins: profile.binCoinsBalance,
          ),
          const SizedBox(height: 16),
          _LevelPath(currentLevel: progress.levelNumber),
          const SizedBox(height: 16),
          B1nGuide(
            asset: AppAssets.b1nReward,
            title: 'Sua jornada está avançando!',
            message: _journeyMessage(progress),
            tone: AppColors.green,
            compact: true,
            portrait: B1nPortraitVariant.celebration,
          ),
          if (widget.onOpenMissions != null) ...[
            const SizedBox(height: 14),
            BingoActionButton(
              label: 'Ver missões',
              icon: Icons.arrow_forward_rounded,
              tone: BingoActionTone.green,
              onPressed: widget.onOpenMissions,
            ),
          ],
          const SizedBox(height: 18),
          _AuthenticatedAccountPanel(
            profile: profile,
            loggingOut: _loggingOut,
            logoutError: _logoutError,
            onLogout: _logout,
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() {
      _loggingOut = true;
      _logoutError = null;
    });
    final failure = await widget.onLogout?.call();
    if (!mounted || failure == null) return;
    setState(() {
      _loggingOut = false;
      _logoutError = failure.message;
    });
  }

  Future<void> _openCustomization(
    BuildContext context,
    ProfileCustomization current, {
    required int currentLevel,
  }) async {
    final selected = await showModalBottomSheet<ProfileCustomization>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ProfileCustomizationSheet(
        initial: current,
        currentLevel: currentLevel,
      ),
    );
    if (selected == null || selected == current || !mounted) return;
    await _store?.saveCustomization(selected);
    if (!mounted) return;
    setState(() => _customization = selected);
  }
}

String _journeyMessage(AuthenticatedProfileProgress progress) {
  if (progress.levelNumber == 0) {
    return 'Faça seu primeiro descarte válido para chegar a Aprendiz.';
  }
  if (progress.levelNumber == 5) {
    return 'Você já fez ${progress.validDepositCount} descartes válidos e alcançou o nível Herói.';
  }
  return 'Você já fez ${progress.validDepositCount} descartes válidos. '
      'Faltam ${progress.remainingToNextLevel} para chegar a '
      '${progress.nextLevelName}.';
}

class _AuthenticatedAccountPanel extends StatelessWidget {
  const _AuthenticatedAccountPanel({
    required this.profile,
    required this.loggingOut,
    required this.logoutError,
    required this.onLogout,
  });

  final AuthenticatedStudentProfile profile;
  final bool loggingOut;
  final String? logoutError;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          _AccountAction(
            icon: Icons.school_outlined,
            label: 'Dados da escola',
            onTap: () => _showSchoolData(context),
          ),
          _AccountAction(
            icon: Icons.logout_rounded,
            label: 'Sair da conta',
            danger: true,
            onTap: loggingOut ? () {} : () => _confirmLogout(context),
          ),
          if (loggingOut) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
          if (logoutError != null) ...[
            const SizedBox(height: 12),
            Text(logoutError!, style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  void _showSchoolData(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dados da escola',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('Aluno: ${profile.name}'),
              Text('Escola: ${profile.schoolName}'),
              Text('Turma: ${profile.className}'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Sair da conta?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: const Text(
          'A sessão autenticada será encerrada neste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onLogout();
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.customization,
    required this.onEdit,
    this.className = '9ºA',
    this.levelNumber = _pilotProfileLevel,
    this.levelName = 'Restaurador',
    this.journeyProgress = 0.62,
  });

  final StudentProfile profile;
  final ProfileCustomization customization;
  final VoidCallback? onEdit;
  final String className;
  final int levelNumber;
  final String? levelName;
  final double journeyProgress;

  @override
  Widget build(BuildContext context) {
    final avatar = _profileAvatars.firstWhere(
      (option) => option.id == customization.avatarId,
      orElse: () => _profileAvatars.first,
    );
    final theme = _profileThemes.firstWhere(
      (option) => option.id == customization.themeId,
      orElse: () => _profileThemes.first,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      tween: Tween(begin: 0.97, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: child),
      ),
      child: PeriodicHighlight(
        colors: [
          theme.primary.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.52),
          theme.secondary.withValues(alpha: 0.08),
        ],
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: AppMotion.standard),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.primary.withValues(alpha: 0.34)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.primary.withValues(alpha: 0.22),
                Colors.white,
                theme.secondary.withValues(alpha: 0.16),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: 4,
                bottom: 0,
                child: _ProfileSparkles(
                  color: theme.primary,
                  reduceMotion: reduceMotion,
                ),
              ),
              Row(
                children: [
                  _ProfileAvatarFrame(
                    asset: avatar.asset,
                    primary: theme.primary,
                    secondary: theme.secondary,
                    size: 94,
                    badge: 'N$levelNumber',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                profile.identifier,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (onEdit != null)
                              IconButton(
                                tooltip: 'Personalizar perfil',
                                onPressed: onEdit,
                                icon: const Icon(Icons.palette_outlined),
                                color: theme.primary,
                              ),
                          ],
                        ),
                        Text('${profile.school} · $className'),
                        const SizedBox(height: 10),
                        BadgeLabel(
                          label: levelNumber == 0
                              ? 'Nível 0'
                              : 'Nível $levelNumber · $levelName',
                          color: theme.primary,
                        ),
                        const SizedBox(height: 8),
                        AnimatedProgressPill(
                          value: journeyProgress,
                          color: theme.secondary,
                          height: 9,
                        ),
                      ],
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

class _ProfileAvatarFrame extends StatelessWidget {
  const _ProfileAvatarFrame({
    required this.asset,
    required this.primary,
    required this.secondary,
    required this.size,
    this.badge,
  });

  final String asset;
  final Color primary;
  final Color secondary;
  final double size;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: 0.16),
                    Colors.white,
                    secondary.withValues(alpha: 0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: primary.withValues(alpha: 0.52),
                  width: 2,
                ),
              ),
              child: BingoAssetImage(
                asset: asset,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  badge!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileSparkles extends StatelessWidget {
  const _ProfileSparkles({required this.color, required this.reduceMotion});

  final Color color;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 760),
      curve: Curves.easeOutBack,
      builder: (context, value, _) => Transform.translate(
        offset: Offset(0, 8 * (1 - value)),
        child: Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: color.withValues(alpha: 0.48),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.recycling_rounded,
                size: 24,
                color: AppColors.green.withValues(alpha: 0.30),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.star_rounded,
                size: 19,
                color: AppColors.warning.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCustomizationSheet extends StatefulWidget {
  const _ProfileCustomizationSheet({
    required this.initial,
    required this.currentLevel,
  });

  final ProfileCustomization initial;
  final int currentLevel;

  @override
  State<_ProfileCustomizationSheet> createState() =>
      _ProfileCustomizationSheetState();
}

class _ProfileCustomizationSheetState
    extends State<_ProfileCustomizationSheet> {
  late String _avatarId = widget.initial.avatarId;
  late String _themeId = widget.initial.themeId;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final selectedAvatar = _profileAvatars.firstWhere(
      (option) => option.id == _avatarId,
      orElse: () => _profileAvatars.first,
    );
    final selectedTheme = _profileThemes.firstWhere(
      (option) => option.id == _themeId,
      orElse: () => _profileThemes.first,
    );

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: DefaultTabController(
        length: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  _ProfileAvatarFrame(
                    asset: selectedAvatar.asset,
                    primary: selectedTheme.primary,
                    secondary: selectedTheme.secondary,
                    size: 68,
                    badge: 'N${widget.currentLevel}',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personalize sua jornada',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${selectedAvatar.label} · ${selectedTheme.label}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const TabBar(
                tabs: [
                  Tab(
                    icon: Icon(Icons.face_retouching_natural),
                    text: 'Avatar',
                  ),
                  Tab(icon: Icon(Icons.palette_outlined), text: 'Tema'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    GridView.builder(
                      itemCount: _profileAvatars.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: largeText ? 2 : 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: largeText ? 0.82 : 0.78,
                      ),
                      itemBuilder: (context, index) {
                        final option = _profileAvatars[index];
                        return _AvatarOptionCard(
                          option: option,
                          selected: option.id == _avatarId,
                          onTap:
                              _isCustomizationUnlocked(
                                option.id,
                                option.requiredLevel,
                                widget.currentLevel,
                              )
                              ? () => setState(() => _avatarId = option.id)
                              : null,
                        );
                      },
                    ),
                    GridView.builder(
                      itemCount: _profileThemes.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: largeText ? 2 : 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: largeText ? 0.95 : 0.88,
                      ),
                      itemBuilder: (context, index) {
                        final option = _profileThemes[index];
                        return _ThemeOptionCard(
                          option: option,
                          selected: option.id == _themeId,
                          onTap:
                              _isCustomizationUnlocked(
                                option.id,
                                option.requiredLevel,
                                widget.currentLevel,
                              )
                              ? () => setState(() => _themeId = option.id)
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BingoActionButton(
                label: 'Salvar personalização',
                icon: Icons.check_rounded,
                tone: BingoActionTone.green,
                onPressed: () => Navigator.of(context).pop(
                  ProfileCustomization(avatarId: _avatarId, themeId: _themeId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isCustomizationUnlocked(
  String optionId,
  int requiredLevel,
  int currentLevel,
) {
  return optionId == 'b1n-default' ||
      optionId == 'city-blue' ||
      requiredLevel <= currentLevel;
}

class _AvatarOptionCard extends StatelessWidget {
  const _AvatarOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ProfileAvatarOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null;
    return Semantics(
      button: !locked,
      selected: selected,
      label: locked
          ? '${option.label}, desbloqueia no nível ${option.requiredLevel}'
          : option.label,
      child: Material(
        color: selected ? AppColors.blue.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.blue : AppColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.blue.withValues(alpha: 0.10),
                              Colors.white,
                              AppColors.green.withValues(alpha: 0.10),
                            ],
                          ),
                        ),
                      ),
                      BingoAssetImage(
                        asset: option.asset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        opacity: AlwaysStoppedAnimation(locked ? 0.34 : 1),
                      ),
                      if (locked)
                        const Center(
                          child: Icon(
                            Icons.lock_rounded,
                            color: AppColors.navy,
                          ),
                        ),
                      if (selected)
                        const Positioned(
                          right: 3,
                          top: 3,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.warning,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  option.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (locked)
                  Text(
                    'Nível ${option.requiredLevel}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
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

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ProfileThemeOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null;
    return Semantics(
      button: !locked,
      selected: selected,
      label: locked
          ? '${option.label}, desbloqueia no nível ${option.requiredLevel}'
          : option.label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? option.primary : AppColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: LinearGradient(
                              colors: [option.primary, option.secondary],
                            ),
                          ),
                        ),
                      ),
                      if (locked)
                        const Center(
                          child: Icon(Icons.lock_rounded, color: Colors.white),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  option.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (locked)
                  Text(
                    'Nível ${option.requiredLevel}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
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

class _ResourceSummary extends StatelessWidget {
  const _ResourceSummary({
    this.personalPoints = '76.000',
    this.personalLabel = 'Pontos pessoais',
    this.classPoints = '119.000',
    this.classLabel = 'Pontos da turma',
    this.binCoins = 12000,
  });

  final String personalPoints;
  final String personalLabel;
  final String classPoints;
  final String classLabel;
  final int binCoins;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 20) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ResourceTile(
              key: const ValueKey('profile-resource-personal'),
              width: width,
              value: personalPoints,
              label: personalLabel,
              icon: Icons.person_rounded,
              color: AppColors.green,
            ),
            _ResourceTile(
              key: const ValueKey('profile-resource-class'),
              width: width,
              value: classPoints,
              label: classLabel,
              icon: Icons.groups_rounded,
              color: AppColors.blue,
            ),
            _ResourceTile(
              key: const ValueKey('profile-resource-bincoins'),
              width: width,
              label: 'BinCoins',
              color: AppColors.warning,
              binCoinValue: binCoins,
            ),
          ],
        );
      },
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.width,
    required this.label,
    required this.color,
    this.value,
    this.icon,
    this.binCoinValue,
    super.key,
  }) : assert(
         binCoinValue != null || (value != null && icon != null),
         'Resource tiles need either BinCoins or a value and icon.',
       );

  final double width;
  final String? value;
  final String label;
  final IconData? icon;
  final Color color;
  final int? binCoinValue;

  @override
  Widget build(BuildContext context) {
    final amount = binCoinValue;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: amount != null
                ? const ExcludeSemantics(child: BinCoinIcon(size: 26))
                : Icon(icon, color: color, size: 26),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: amount != null
                ? BinCoinAmount(
                    value: amount,
                    showIcon: false,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 16, height: 1),
                  )
                : Text(
                    value!,
                    maxLines: 1,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 16, height: 1),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ExcludeSemantics(
            excluding: amount != null,
            child: Text(
              label,
              maxLines: 2,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(height: 1),
            ),
          ),
        ),
      ],
    );

    return Container(
      width: width,
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: content,
    );
  }
}

class _LevelPath extends StatelessWidget {
  const _LevelPath({required this.currentLevel});

  final int currentLevel;

  static const _levels = [
    'Aprendiz',
    'Explorador',
    'Restaurador',
    'Guardião',
    'Herói',
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trilha do restaurador',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < _levels.length; index++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: currentLevel > 0 && index < currentLevel
                              ? AppColors.green
                              : Colors.white,
                          border: Border.all(
                            color: index == currentLevel - 1
                                ? AppColors.blue
                                : AppColors.green,
                            width: index == currentLevel - 1 ? 3 : 2,
                          ),
                        ),
                        child: index < currentLevel - 1
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: index == currentLevel - 1
                                      ? Colors.white
                                      : AppColors.navy,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                      const SizedBox(height: 7),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _levels[index],
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < _levels.length - 1)
                  Container(
                    width: 8,
                    height: 3,
                    margin: const EdgeInsets.only(top: 18),
                    color: index < currentLevel - 1
                        ? AppColors.green
                        : AppColors.line,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.profile,
    required this.repository,
    required this.onExitPilot,
  });

  final StudentProfile profile;
  final ProfileRepository? repository;
  final Future<void> Function()? onExitPilot;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          _AccountAction(
            icon: Icons.school_outlined,
            label: 'Dados da escola',
            onTap: () => _showSchoolData(context),
          ),
          if (repository != null)
            _AccountAction(
              icon: Icons.password_rounded,
              label: 'Redefinir PIN',
              onTap: () => _changePin(context),
            ),
          _AccountAction(
            icon: Icons.swap_horiz_rounded,
            label: repository == null ? 'Sair do modo piloto' : 'Trocar conta',
            danger: true,
            onTap: () => _leaveAccount(context),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ChangePinScreen(repository: repository!, profile: profile),
      ),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN atualizado neste aparelho.')),
      );
    }
  }

  void _showSchoolData(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dados da escola',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('Aluno: ${profile.identifier}'),
              Text('Escola: ${profile.school}'),
              const Text('Turma: 9ºA'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          repository == null ? 'Sair do piloto?' : 'Trocar conta?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          repository == null
              ? 'Você voltará para o início da demonstração.'
              : 'O perfil e o PIN salvos neste aparelho serão removidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (repository == null && onExitPilot != null) {
      await onExitPilot!();
      return;
    }
    await repository?.deleteProfile();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => AccessFlowScreen(repository: repository),
      ),
      (_) => false,
    );
  }
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.blue;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: danger ? AppColors.danger : AppColors.navy,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}
