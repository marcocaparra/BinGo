import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import 'shell_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Entrar no BinGo!',
      subtitle: 'Acompanhe missões, pontos da turma e recompensas.',
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneTransition,
            title: 'Descarte eletrônico com validação',
            subtitle:
                'O Totem confirma o descarte. O app mostra impacto e progresso.',
            height: 178,
          ),
          const SizedBox(height: 18),
          BingoActionButton(
            label: 'Entrar no piloto',
            icon: Icons.science_outlined,
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const ShellScreen()),
              (_) => false,
            ),
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                BadgeLabel(label: 'Piloto escolar futuro'),
                SizedBox(height: 14),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Escola',
                    hintText: 'ENIAC',
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(labelText: 'Nome ou matrícula'),
                ),
                SizedBox(height: 12),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    helperText: 'Use o PIN informado pela sua escola.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const B1nTipCard(
            title: 'Como funciona',
            message:
                'O descarte real acontece no Totem. O app mostra a missão, a validação e o impacto.',
            tone: AppColors.blue,
          ),
        ],
      ),
    );
  }
}
