import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/b1n_guide.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.onGoHome, this.onExitPilot, super.key})
    : remoteProfile = null,
      onLogout = null,
      loggingOut = false,
      logoutError = null;

  const ProfileScreen.authenticated({
    required StudentProfile profile,
    required this.onLogout,
    this.loggingOut = false,
    this.logoutError,
    super.key,
  }) : remoteProfile = profile,
       onGoHome = null,
       onExitPilot = null;

  final VoidCallback? onGoHome;
  final Future<void> Function()? onExitPilot;
  final StudentProfile? remoteProfile;
  final VoidCallback? onLogout;
  final bool loggingOut;
  final String? logoutError;

  @override
  Widget build(BuildContext context) {
    final remote = remoteProfile;
    final profile = remote == null
        ? const _DisplayedProfile(
            school: 'ENIAC',
            identifier: 'Marco Caparra',
            className: '9ºA',
          )
        : _DisplayedProfile(
            school: remote.schoolName,
            identifier: remote.name,
            className: remote.className,
          );
    return AppPage(
      title: remote == null ? 'Seu caminho' : 'Seu perfil',
      subtitle: remote == null
          ? 'Progresso, conquistas e conta em um só lugar.'
          : 'Dados reais da sua conta vinculada.',
      showBackButton: false,
      dataStatus: remote == null ? AppDataStatus.local : AppDataStatus.remote,
      child: Column(
        children: [
          _ProfileHeader(profile: profile, showLevel: remote == null),
          const SizedBox(height: 16),
          _ResourceSummary(profile: remote),
          if (remote == null) ...[
            const SizedBox(height: 16),
            const _LevelPath(),
            const SizedBox(height: 16),
            const B1nGuide(
              asset: AppAssets.b1nReward,
              title: 'Você está avançando!',
              message: 'Faltam 240 pontos pessoais para chegar a Guardião.',
              tone: AppColors.green,
              compact: true,
            ),
            const SizedBox(height: 14),
            BingoActionButton(
              label: 'Continuar minha missão',
              icon: Icons.arrow_forward_rounded,
              tone: BingoActionTone.green,
              onPressed: onGoHome,
            ),
          ],
          const SizedBox(height: 18),
          _AccountPanel(
            profile: profile,
            onExitPilot: onExitPilot,
            onLogout: onLogout,
            authenticated: remote != null,
          ),
          if (loggingOut) ...[
            const SizedBox(height: 16),
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
}

class _DisplayedProfile {
  const _DisplayedProfile({
    required this.school,
    required this.identifier,
    required this.className,
  });

  final String school;
  final String identifier;
  final String className;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.showLevel});

  final _DisplayedProfile profile;
  final bool showLevel;

  String get _initials {
    final parts = profile.identifier.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'B!';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.blue.withValues(alpha: 0.12),
            Colors.white,
            AppColors.green.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.blue, AppColors.green],
              ),
            ),
            child: Text(
              _initials,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.identifier,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text('${profile.school} · ${profile.className}'),
                if (showLevel) ...[
                  const SizedBox(height: 10),
                  const BadgeLabel(label: 'Nível 3 · Restaurador'),
                  const SizedBox(height: 8),
                  const AnimatedProgressPill(value: 0.62, height: 9),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceSummary extends StatelessWidget {
  const _ResourceSummary({this.profile});

  final StudentProfile? profile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final remote = profile;
        final itemCount = remote == null ? 3 : 2;
        final width =
            (constraints.maxWidth - (10 * (itemCount - 1))) / itemCount;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (remote == null)
              _ResourceTile(
                key: const ValueKey('profile-resource-personal'),
                width: width,
                value: '760',
                label: 'Pontos pessoais',
                icon: Icons.person_rounded,
                color: AppColors.green,
              ),
            _ResourceTile(
              key: const ValueKey('profile-resource-class'),
              width: width,
              value: remote?.classXpBalance.toString() ?? '1.190',
              label: remote == null ? 'Pontos da turma' : 'XP da turma',
              icon: Icons.groups_rounded,
              color: AppColors.blue,
            ),
            _ResourceTile(
              key: const ValueKey('profile-resource-bincoins'),
              width: width,
              label: 'BinCoins',
              color: AppColors.warning,
              binCoinValue: remote?.binCoinsBalance ?? 120,
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
  const _LevelPath();

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
                          color: index < 3 ? AppColors.green : Colors.white,
                          border: Border.all(
                            color: index == 2
                                ? AppColors.blue
                                : AppColors.green,
                            width: index == 2 ? 3 : 2,
                          ),
                        ),
                        child: index < 2
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: index == 2
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
                    color: index < 2 ? AppColors.green : AppColors.line,
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
    required this.onExitPilot,
    required this.onLogout,
    required this.authenticated,
  });

  final _DisplayedProfile profile;
  final Future<void> Function()? onExitPilot;
  final VoidCallback? onLogout;
  final bool authenticated;

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
            icon: authenticated
                ? Icons.logout_rounded
                : Icons.swap_horiz_rounded,
            label: authenticated ? 'Sair da conta' : 'Sair do modo piloto',
            danger: true,
            onTap: authenticated ? onLogout! : () => _leavePilot(context),
          ),
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
              Text('Aluno: ${profile.identifier}'),
              Text('Escola: ${profile.school}'),
              Text('Turma: ${profile.className}'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leavePilot(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Sair do piloto?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: const Text('Você voltará para o início da demonstração.'),
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
    await onExitPilot?.call();
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
