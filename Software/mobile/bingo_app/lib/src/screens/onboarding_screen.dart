import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';
import 'access_flow_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({this.repository, super.key});

  final ProfileRepository? repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            AppAssets.sceneTransition,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.16),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 430,
                        minHeight: constraints.maxHeight - 52,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _GlassSurface(
                            fillOpacity: 0.34,
                            blurSigma: 8,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            child: SizedBox(
                              width: 246,
                              height: 70,
                              child: Image.asset(
                                AppAssets.logoOfficialOnboardingClean,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _GlassSurface(
                            fillOpacity: 0.24,
                            blurSigma: 8,
                            child: Column(
                              children: [
                                Image.asset(
                                  AppAssets.b1nPoseOnboardingClean,
                                  height: 128,
                                  filterQuality: FilterQuality.high,
                                ),
                                Text(
                                  'Ajude BinGópolis',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.displaySmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Complete missões de descarte, recupere setores da cidade e ganhe BinCoins no caminho.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.navy.withValues(
                                          alpha: 0.78,
                                        ),
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 18),
                                const _FlowSteps(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          BingoActionButton(
                            label: 'Começar missão',
                            tone: BingoActionTone.green,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AccessFlowScreen(repository: repository),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.fillOpacity,
    this.blurSigma = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? fillOpacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(20));
    final shadowColor = AppColors.navy.withValues(alpha: 0.10);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: fillOpacity ?? 0.54),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FlowSteps extends StatelessWidget {
  const _FlowSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.devices_other_rounded, 'Prepare', AppColors.blue),
      (Icons.directions_walk_rounded, 'Vá ao Totem', AppColors.green),
      (Icons.verified_rounded, 'Valide', AppColors.scr4p),
      (Icons.bolt_rounded, 'Impacte', AppColors.warning),
    ];
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Column(
      children: [
        Text(
          'Rota do descarte',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Positioned(
              left: 32,
              right: 32,
              top: 23,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    colors: [AppColors.blue, AppColors.green, AppColors.scr4p],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var index = 0; index < steps.length; index++)
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.78, end: 1),
                      duration: Duration(
                        milliseconds: reduceMotion ? 0 : 360 + (index * 90),
                      ),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: Column(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: steps[index].$3.withValues(
                                    alpha: 0.16,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: steps[index].$3,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: Icon(
                                    steps[index].$1,
                                    color: steps[index].$3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              steps[index].$2,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
