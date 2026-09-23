export 'b1n_context_message.dart';
export 'b1n_dialogue_strip.dart';
export 'bingo_asset_image.dart';
export 'bincoin_amount.dart';
export 'impact_comparison.dart';

import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import 'bincoin_amount.dart';
import 'bingo_asset_image.dart';

enum AppDataStatus { simulated, local, remote }

enum BingoDataStateKind { empty, loading }

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions,
    this.showBackButton = true,
    this.dataStatus = AppDataStatus.simulated,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool showBackButton;
  final AppDataStatus? dataStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (dataStatus != null && dataStatus != AppDataStatus.remote)
            _DataStatusNotice(status: dataStatus!),
          ...?actions,
        ],
        automaticallyImplyLeading: showBackButton,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataStatusNotice extends StatelessWidget {
  const _DataStatusNotice({required this.status});

  final AppDataStatus status;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final (message, label) = switch (status) {
      AppDataStatus.simulated => (
        'Dados simulados. A atualização real acontecerá pelo Totem.',
        'Dados simulados',
      ),
      AppDataStatus.local => (
        'Dados salvos localmente neste aparelho.',
        'Perfil local',
      ),
      AppDataStatus.remote => (
        'Dados reais permitidos para a sessão autenticada.',
        'Dados autenticados',
      ),
    };
    return Tooltip(
      message: message,
      child: Semantics(
        label: label,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SizedBox(
            width: largeText ? 180 : 118,
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w800,
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

class BingoDataState extends StatelessWidget {
  const BingoDataState({
    required this.kind,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final BingoDataStateKind kind;
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: kind == BingoDataStateKind.loading,
      label: '$title. $message',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            if (kind == BingoDataStateKind.loading)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(icon, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ImageHeroCard extends StatelessWidget {
  const ImageHeroCard({
    required this.image,
    required this.title,
    required this.subtitle,
    this.badge,
    this.height = 190,
    this.progress,
    this.progressColor = AppColors.green,
    this.alignment = Alignment.center,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String image;
  final String title;
  final String subtitle;
  final String? badge;
  final double height;
  final double? progress;
  final Color progressColor;
  final Alignment alignment;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsiveHeight = constraints.maxWidth * 0.54;
        final baseHeight = height > responsiveHeight
            ? height
            : responsiveHeight;
        final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final largeTextMinimum = constraints.maxWidth < 340 ? 460.0 : 430.0;
        final effectiveHeight = usesLargeText && baseHeight < largeTextMinimum
            ? largeTextMinimum
            : baseHeight;
        final maximumHeight = usesLargeText ? 480.0 : 230.0;

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: effectiveHeight.clamp(168.0, maximumHeight),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: AppColors.navy,
                  child: BingoAssetImage(
                    asset: image,
                    fit: fit,
                    alignment: alignment,
                    semanticLabel: title,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.navy.withValues(alpha: 0.18),
                        AppColors.navy.withValues(alpha: 0.76),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (badge != null) BadgeLabel(label: badge!),
                      if (badge != null) const SizedBox(height: 8),
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 14,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 14),
                        AnimatedProgressPill(
                          value: progress!,
                          color: progressColor,
                          backgroundColor: Colors.white.withValues(alpha: 0.78),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AnimatedProgressPill extends StatelessWidget {
  const AnimatedProgressPill({
    required this.value,
    this.color = AppColors.green,
    this.backgroundColor = AppColors.line,
    this.height = 12,
    super.key,
  });

  final double value;
  final Color color;
  final Color backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            height: height,
            color: backgroundColor,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clampedValue),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, animatedValue, _) {
                return Container(
                  width: constraints.maxWidth * animatedValue,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return BinCoinIcon(size: size);
  }
}

class BadgeLabel extends StatelessWidget {
  const BadgeLabel({required this.label, this.color = Colors.white, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class MissionCard extends StatelessWidget {
  const MissionCard({required this.mission, required this.onTap, super.key});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: mission.color,
              child: const Icon(Icons.recycling, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(mission.subtitle),
                  const SizedBox(height: 12),
                  AnimatedProgressPill(
                    value: mission.progress,
                    height: 9,
                    color: mission.color,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MissionRewardIcon(mission: mission),
                      const SizedBox(width: 6),
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
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _MissionRewardIcon extends StatelessWidget {
  const _MissionRewardIcon({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    if (mission.reward.toLowerCase().contains('setor')) {
      return const Icon(Icons.map_outlined, size: 20, color: AppColors.blue);
    }

    return const CoinIcon(size: 20);
  }
}

class B1nTipCard extends StatelessWidget {
  const B1nTipCard({
    required this.title,
    required this.message,
    this.tone = AppColors.blue,
    this.asset = AppAssets.b1nIcon,
    this.onTap,
    super.key,
  });

  final String title;
  final String message;
  final Color tone;
  final String asset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: tone.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            BingoAssetImage(
              asset: asset,
              height: 54,
              width: 54,
              semanticLabel: title,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    required this.value,
    required this.label,
    this.icon,
    super.key,
  });

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          if (label == 'BinCoins') const CoinIcon(size: 24),
          if (label != 'BinCoins' && icon != null)
            Icon(icon, color: AppColors.blue),
          if (label == 'BinCoins' || icon != null) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
