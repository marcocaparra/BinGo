import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
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
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.92),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.navy.withValues(alpha: 0.10),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              AppAssets.logoOfficialTransparent,
                              height: 54,
                            ),
                          ),
                          const SizedBox(height: 28),
                          SurfaceCard(
                            child: Column(
                              children: [
                                Image.asset(AppAssets.b1nPose, height: 128),
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
                                  style: Theme.of(context).textTheme.bodyMedium,
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
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: steps[index].$3,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: steps[index].$3.withValues(
                                    alpha: 0.18,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              steps[index].$1,
                              color: steps[index].$3,
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
