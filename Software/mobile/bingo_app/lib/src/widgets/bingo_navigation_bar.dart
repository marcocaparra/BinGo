import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BingoNavigationBar extends StatelessWidget {
  const BingoNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Início'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Carteira'),
    (Icons.verified_outlined, Icons.verified_rounded, 'Missões'),
    (Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'Ranking'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / _destinations.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    key: Key('bingo-nav-indicator-$selectedIndex'),
                    duration: Duration(
                      milliseconds: reduceMotion ? 0 : AppMotion.standard,
                    ),
                    curve: Curves.easeOutCubic,
                    left: (segmentWidth * selectedIndex) + 6,
                    top: 7,
                    width: segmentWidth - 12,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.24),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.blue.withValues(alpha: 0.14),
                            AppColors.green.withValues(alpha: 0.12),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < _destinations.length; index++)
                        Expanded(
                          child: _NavigationDestination(
                            key: Key('bingo-nav-destination-$index'),
                            icon: _destinations[index].$1,
                            selectedIcon: _destinations[index].$2,
                            label: _destinations[index].$3,
                            selected: selectedIndex == index,
                            reduceMotion: reduceMotion,
                            onTap: () => onSelected(index),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(
      milliseconds: reduceMotion ? 0 : AppMotion.standard,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: AnimatedSlide(
              duration: duration,
              curve: Curves.easeOutBack,
              offset: selected ? const Offset(0, -0.08) : Offset.zero,
              child: AnimatedScale(
                duration: duration,
                curve: Curves.easeOutBack,
                scale: selected ? 1.06 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 23,
                      color: selected ? AppColors.blue : AppColors.textMuted,
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected ? AppColors.navy : AppColors.textMuted,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
