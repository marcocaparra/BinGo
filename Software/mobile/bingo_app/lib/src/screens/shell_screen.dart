import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../data/profile_repository.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_navigation_bar.dart';
import '../widgets/bingo_widgets.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({this.initialIndex = 0, this.repository, super.key});

  final int initialIndex;
  final ProfileRepository? repository;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenTab: _selectTab),
      const WalletScreen(),
      const MissionsScreen(),
      const RankingScreen(),
      const ProfileScreen(),
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onOpenTab, super.key});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Olá, Marco!',
      subtitle: 'Faltam 2 descartes para recuperar outro setor da Praça.',
      showBackButton: false,
      actions: [
        IconButton(
          tooltip: 'Como funciona',
          onPressed: () => _push(context, const HowItWorksScreen()),
          icon: const Icon(Icons.help_outline),
        ),
      ],
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneClean,
            badge: 'Praça Central',
            title: '68% restaurada',
            subtitle: 'Descarte certo, seguro e validado recupera setores.',
            progress: 0.68,
          ),
          const SizedBox(height: 18),
          B1nTipCard(
            title: 'Alerta SCR4P',
            message:
                'SCR4P avança quando itens eletrônicos ficam no lixo comum.',
            tone: AppColors.scr4p,
            asset: AppAssets.scr4pIcon,
            onTap: () => _push(context, const Scr4pInfoScreen()),
          ),
          const SizedBox(height: 18),
          MissionCard(
            mission: activeMission,
            onTap: () => _push(
              context,
              const MissionDetailScreen(mission: activeMission),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Começar no Totem',
            color: AppColors.green,
            icon: Icons.directions_walk,
            onPressed: () => _push(
              context,
              const TotemTrackingScreen(mission: activeMission),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: StatTile(
                  value: '120',
                  label: 'BinCoins',
                  icon: Icons.bolt,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: StatTile(
                  value: '8',
                  label: 'Descartes',
                  icon: Icons.recycling,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SoftAction(
            label: 'Ver impacto da turma',
            icon: Icons.auto_graph,
            onTap: () => _push(context, const ImpactScreen()),
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
      title: 'Missão: ${mission.title.toLowerCase()}',
      subtitle: 'O app orienta. O descarte acontece no Totem físico.',
      child: Column(
        children: [
          ImageHeroCard(
            image: mission.image,
            title: mission.detailTitle,
            subtitle: mission.detailText,
            height: 188,
            progress: mission.progress,
            progressColor: mission.color,
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: Column(
              children: [
                for (var i = 0; i < mission.steps.length; i++)
                  _StepRow(
                    number: '${i + 1}',
                    title: mission.steps[i].$1,
                    text: mission.steps[i].$2,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Entendi, vou ao Totem',
            color: AppColors.green,
            icon: Icons.directions_walk,
            onPressed: () =>
                _push(context, TotemTrackingScreen(mission: mission)),
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
      subtitle: 'Acompanhe a validação do descarte físico.',
      child: Column(
        children: [
          SurfaceCard(
            color: AppColors.blue.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(AppAssets.b1nIcon, height: 54, width: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        mission.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _StepRow(
                  number: '1',
                  title: 'Item autorizado',
                  text: 'Use apenas item sem uso, com autorização e sem risco.',
                ),
                const _StepRow(
                  number: '2',
                  title: 'Aguardando Totem',
                  text: 'Escolha sua turma e descarte no local indicado.',
                ),
                _StepRow(
                  number: '3',
                  title: 'Validação no app',
                  text: '${mission.reward} entram após confirmação.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const B1nTipCard(
            title: 'BinGo recompensa responsabilidade',
            message:
                'Não compre, quebre ou pegue item de outra pessoa para ganhar pontos.',
            tone: AppColors.warning,
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                _StepRow(
                  number: '✓',
                  title: 'Pode descartar',
                  text:
                      'Cabos, mouse, fone, controle pequeno e acessórios secos.',
                ),
                _StepRow(
                  number: '!',
                  title: 'Chame um professor',
                  text:
                      'Celular, bateria solta, item trincado ou peça com ponta exposta.',
                ),
                _StepRow(
                  number: '×',
                  title: 'Não toque',
                  text: 'Bateria inchada, vazando, molhada ou quente.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Ver impacto',
            color: AppColors.green,
            icon: Icons.auto_graph,
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const ImpactScreen()),
              (_) => false,
            ),
          ),
        ],
      ),
    );
  }
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final redeemableRewards = rewards
        .where((reward) => reward.available)
        .length;

    return AppPage(
      title: 'Carteira',
      subtitle: 'Seus BinCoins e resgates.',
      showBackButton: false,
      child: Column(
        children: [
          SurfaceCard(
            color: const Color(0xFFFFF4C7),
            child: Row(
              children: [
                Image.asset(AppAssets.bincoinV2, height: 64, width: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$userBinCoins BinCoins',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Você já pode resgatar $redeemableRewards recompensas.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Abrir BinBazar',
            icon: Icons.storefront,
            onPressed: () => _push(context, const RewardsScreen()),
          ),
          const SizedBox(height: 18),
          const _HistoryTile(
            title: '+10 BinCoins',
            subtitle: 'Missão rápida concluída',
          ),
          const _HistoryTile(
            title: '-30 BinCoins',
            subtitle: 'Suco natural resgatado',
          ),
          const _HistoryTile(
            title: '+20 BinCoins',
            subtitle: 'Bônus de setor liberado',
          ),
        ],
      ),
    );
  }
}

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final redeemableRewards = rewards
        .where((reward) => reward.available)
        .length;

    return AppPage(
      title: 'BinBazar',
      subtitle: 'O balcão de recompensas do Tio B3N.',
      child: Column(
        children: [
          SurfaceCard(
            color: const Color(0xFFEAFBF3),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 112,
                  child: Image.asset(AppAssets.b3nTioB1n, fit: BoxFit.contain),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tio B3N cuida do balcão',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Você tem $userBinCoins BinCoins e $redeemableRewards resgates disponíveis.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final reward in rewards) ...[
            _RewardTile(reward: reward),
            const SizedBox(height: 12),
          ],
          const B1nTipCard(
            title: 'Recado do Tio B3N',
            message:
                'Reserve no app e confirme a retirada com a escola antes de pegar o prêmio.',
            tone: AppColors.green,
            asset: AppAssets.b3nTioB1n,
          ),
        ],
      ),
    );
  }
}

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Missões',
      subtitle: 'Sua trilha de recuperação.',
      showBackButton: false,
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneConfrontation,
            title: 'B1N vs SCR4P',
            subtitle: 'Cada descarte enfraquece a corrupção.',
            height: 178,
          ),
          const SizedBox(height: 18),
          for (final mission in missions) ...[
            MissionCard(
              mission: mission,
              onTap: () => mission.color == AppColors.scr4p
                  ? _push(context, const Scr4pAlertScreen())
                  : _push(context, MissionDetailScreen(mission: mission)),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class Scr4pAlertScreen extends StatelessWidget {
  const Scr4pAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Alerta SCR4P',
      subtitle: 'Evento de turma com recompensa extra.',
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneCorruptScr4p,
            badge: 'Evento ativo',
            title: 'Defesa da Praça',
            subtitle: 'Descarte 5 itens em turma até sexta.',
            height: 180,
            alignment: Alignment.centerRight,
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(AppAssets.scr4pIcon, height: 50, width: 50),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SCR4P ainda controla 58% do setor',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const AnimatedProgressPill(value: 0.58, color: AppColors.scr4p),
                const SizedBox(height: 10),
                const Text(
                  'Faltam 3 descartes para ganhar +20 BinCoins por aluno participante.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            color: Color(0xFFF4ECFF),
            child: Column(
              children: [
                _StepRow(
                  number: '+20',
                  title: 'Participou da defesa',
                  text: 'Todo aluno com descarte validado ganha bônus.',
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '+35',
                  title: 'Contribuição forte',
                  text: 'Quem validar 3 itens no evento recebe bônus maior.',
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '+50',
                  title: 'Herói contra SCR4P',
                  text: 'Os maiores contribuidores ganham bônus de defesa.',
                  color: AppColors.scr4p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Ver passo a passo',
            color: AppColors.scr4p,
            icon: Icons.shield,
            onPressed: () => _push(
              context,
              MissionDetailScreen(
                mission: missions.firstWhere(
                  (mission) => mission.id == 'scr4p-defense',
                ),
              ),
            ),
          ),
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
      subtitle: 'O vilão que cresce quando o descarte vai para o lugar errado.',
      child: Column(
        children: [
          ImageHeroCard(
            image: AppAssets.sceneCorruptScr4p,
            badge: 'Alerta ativo',
            title: 'Corrupção eletrônica',
            subtitle: 'Cada item no lixo comum fortalece SCR4P.',
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
                    'SCR4P tenta corromper os cenários de BinGópolis. Para enfraquecê-lo, sua turma precisa validar descartes no Totem.',
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
                  title: 'Ele ataca cenários',
                  text:
                      'Praças, parques e lugares sazonais podem ficar corrompidos.',
                ),
                _StepRow(
                  number: '2',
                  title: 'A turma limpa setores',
                  text: 'Cada descarte validado recupera uma parte do cenário.',
                ),
                _StepRow(
                  number: '3',
                  title: 'Quem ajuda mais ganha mais',
                  text:
                      'Eventos SCR4P dão bônus por participação e contribuição.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Ver defesa ativa',
            color: AppColors.scr4p,
            icon: Icons.shield,
            onPressed: () => _push(context, const Scr4pAlertScreen()),
          ),
        ],
      ),
    );
  }
}

class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Ranking da turma',
      subtitle: 'Veja quem está perto de recuperar mais setores.',
      showBackButton: false,
      child: Column(
        children: [
          const _PodiumCard(),
          const SizedBox(height: 18),
          const SurfaceCard(
            color: Color(0xFFE9FBEA),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.green,
                  child: Text(
                    '4º',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sua turma · 9ºA',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text('Faltam 50 pts para entrar no top 3.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          B1nTipCard(
            title: 'Cenário atual: Praça Central',
            message:
                'A disputa deste mês acontece na Praça. Toque para ver setores e progresso.',
            tone: AppColors.blue,
            asset: AppAssets.b1nIcon,
            onTap: () => _push(context, const CurrentScenarioScreen()),
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            color: Color(0xFFFFF8E6),
            child: Row(
              children: [
                Icon(Icons.card_giftcard, color: AppColors.warning),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Prêmios do ciclo: top 3 turmas e participação segura ganham bônus.',
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

class CurrentScenarioScreen extends StatelessWidget {
  const CurrentScenarioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Cenário atual',
      subtitle: 'Onde o ciclo do ranking está acontecendo.',
      child: Column(
        children: const [
          ImageHeroCard(
            image: AppAssets.sceneConfrontation,
            badge: 'Praça Central',
            title: '86% em disputa',
            subtitle: 'Setores restaurados pela soma de pontos das turmas.',
            height: 178,
            progress: 0.86,
            progressColor: AppColors.warning,
          ),
          SizedBox(height: 18),
          SurfaceCard(
            color: Color(0xFFEAF7FF),
            child: Column(
              children: [
                _StepRow(
                  number: '1',
                  title: 'Cenário',
                  text: 'É o lugar grande que o SCR4P está atacando agora.',
                ),
                _StepRow(
                  number: '2',
                  title: 'Setores',
                  text: 'São as partes recuperadas quando a turma descarta.',
                ),
                _StepRow(
                  number: '12',
                  title: 'Ciclo',
                  text:
                      'Quando acaba, os pontos da turma reiniciam e os prêmios saem.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImpactScreen extends StatelessWidget {
  const ImpactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Impacto',
      subtitle: 'Veja como sua turma mudou a cidade.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _BeforeAfter(image: impactImages[0], label: 'Antes'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BeforeAfter(image: impactImages[1], label: 'Agora'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            color: AppColors.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '68%',
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: Colors.white),
                ),
                Text(
                  'da Praça Central recuperada',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 16),
                const AnimatedProgressPill(
                  value: 0.68,
                  color: AppColors.green,
                  backgroundColor: Colors.white24,
                  height: 14,
                ),
                const SizedBox(height: 12),
                Text(
                  'Faltam 2 descartes para liberar um setor.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(
                child: StatTile(value: '8', label: 'Descartes'),
              ),
              SizedBox(width: 14),
              Expanded(
                child: StatTile(value: '12', label: 'Alunos ativos'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                _StepRow(
                  number: '1',
                  title: '3,2 kg fora do lixo comum',
                  text: 'Cabos, mouses e acessórios enviados para triagem.',
                ),
                _StepRow(
                  number: '2',
                  title: '12 alunos participaram',
                  text: 'O impacto é da turma, não só de quem lidera.',
                ),
                _StepRow(
                  number: '3',
                  title: '2 descartes para novo setor',
                  text: 'Quando bater a meta, a cidade muda visualmente.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Ver história da praça',
            icon: Icons.auto_stories,
            onPressed: () => _push(context, const StoryScreen()),
          ),
        ],
      ),
    );
  }
}

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'História',
      subtitle: 'Os estados da Praça Central.',
      child: Column(
        children: const [
          ImageHeroCard(
            image: AppAssets.sceneClean,
            title: 'Limpa',
            subtitle: 'A cidade protegida por descartes corretos.',
          ),
          SizedBox(height: 12),
          ImageHeroCard(
            image: AppAssets.sceneTransition,
            title: 'Transição',
            subtitle: 'A turma está recuperando o setor.',
          ),
          SizedBox(height: 12),
          ImageHeroCard(
            image: AppAssets.sceneConfrontation,
            title: 'Confronto',
            subtitle: 'B1N e SCR4P disputam a praça.',
          ),
          SizedBox(height: 18),
          B1nTipCard(
            title: 'B1N protege',
            message:
                'O descarte correto fortalece a cidade. O descarte errado alimenta a corrupção.',
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Perfil',
      subtitle: 'Seu progresso, turma e conquistas.',
      showBackButton: false,
      child: Column(
        children: [
          SurfaceCard(
            child: Row(
              children: [
                Image.asset(AppAssets.b1nIcon, height: 92, width: 92),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marco Caparra',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const BadgeLabel(
                        label: 'Nível 3 · Restaurador',
                        color: Color(0xFFE9FBEA),
                      ),
                      const SizedBox(height: 10),
                      const AnimatedProgressPill(value: 0.62, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(
                child: StatTile(value: 'Nível 3', label: 'Restaurador'),
              ),
              SizedBox(width: 14),
              Expanded(
                child: StatTile(value: '760', label: 'Pts pessoais'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                _StepRow(
                  number: '1',
                  title: 'Pontos da turma',
                  text: 'Valem no ciclo do cenário.',
                ),
                _StepRow(
                  number: '2',
                  title: 'Pontos pessoais',
                  text: 'Sobem seu nível e mostram sua evolução.',
                ),
                _StepRow(
                  number: '3',
                  title: 'BinCoins',
                  text: 'São moedas para trocar no BinBazar.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            color: AppColors.blue.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Conquista ativa: 5 descartes validados em BinGópolis',
                    style: Theme.of(context).textTheme.titleMedium,
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
                  title: 'Aprendiz',
                  text: 'Começa a validar descartes e entender os cenários.',
                ),
                _StepRow(
                  number: '2',
                  title: 'Explorador',
                  text: 'Ganha acesso antecipado a dicas de missões.',
                ),
                _StepRow(
                  number: '3',
                  title: 'Restaurador',
                  text: 'Você está aqui: já ajuda a recuperar setores.',
                ),
                _StepRow(
                  number: '4',
                  title: 'Guardião',
                  text: 'Protege a turma com descartes seguros e validados.',
                ),
                _StepRow(
                  number: '5',
                  title: 'Herói',
                  text: 'Topo do ciclo: destaque visual pela responsabilidade.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SoftAction(
            label: 'Meus dados',
            icon: Icons.badge_outlined,
            onTap: () => _push(
              context,
              const InfoScreen(
                title: 'Meus dados',
                subtitle: 'Identificação usada pela escola.',
                icon: Icons.badge_outlined,
                lines: [
                  ('Aluno', 'Marco Caparra'),
                  ('Turma', '9ºA'),
                  ('Escola', 'ENIAC'),
                ],
              ),
            ),
          ),
          _SoftAction(
            label: 'Minha turma',
            icon: Icons.groups_outlined,
            onTap: () => _push(
              context,
              const InfoScreen(
                title: 'Minha turma',
                subtitle: 'Progresso coletivo da sala.',
                icon: Icons.groups_outlined,
                lines: [
                  ('Posição da turma', '4º lugar'),
                  ('Hoje', '+210 pontos'),
                  ('Meta', '50 pts para subir posição'),
                ],
              ),
            ),
          ),
          _SoftAction(
            label: 'Meus resgates',
            icon: Icons.redeem_outlined,
            onTap: () => _push(
              context,
              const InfoScreen(
                title: 'Meus resgates',
                subtitle: 'Histórico de recompensas.',
                icon: Icons.redeem_outlined,
                lines: [
                  ('Suco natural', 'Retirado hoje'),
                  ('Vale cantina', 'Disponível'),
                  ('Prêmio surpresa', 'Faltam 60 BinCoins'),
                ],
              ),
            ),
          ),
          _SoftAction(
            label: 'Como funciona',
            icon: Icons.help_outline,
            onTap: () => _push(context, const HowItWorksScreen()),
          ),
        ],
      ),
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
      subtitle: 'Bem simples: Totem físico + app.',
      child: Column(
        children: const [
          SurfaceCard(
            child: Column(
              children: [
                _StepRow(
                  number: '1',
                  title: 'Vá até o Totem físico',
                  text: 'Ele fica em um ponto combinado da escola.',
                ),
                _StepRow(
                  number: '2',
                  title: 'Escolha sua turma no Totem',
                  text: 'Assim os pontos vão para você e sua sala.',
                ),
                _StepRow(
                  number: '3',
                  title: 'Descarte corretamente',
                  text: 'Coloque o eletrônico no local indicado.',
                ),
                _StepRow(
                  number: '4',
                  title: 'Veja pontos e impacto no app',
                  text:
                      'BinCoins, pontos e cenário atualizam depois da validação.',
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          B1nTipCard(
            title: 'Importante',
            message:
                'As telas do Totem serão feitas depois. Por enquanto, o app já deixa claro o caminho físico.',
          ),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.reward});

  final RewardItem reward;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: reward.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: reward.color.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(reward.icon, color: reward.color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const CoinIcon(size: 18),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${reward.cost} BinCoins',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: reward.available
                  ? () => _showSnack(
                      context,
                      '${reward.title} reservado. Confirme a retirada na escola.',
                    )
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: reward.available
                    ? AppColors.green
                    : AppColors.line,
                foregroundColor: reward.available
                    ? Colors.white
                    : AppColors.textMuted,
              ),
              child: Text(reward.status),
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: const Color(0xFFEAF7FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Top turmas da Praça',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const BadgeLabel(label: '12 dias'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                child: _PodiumPlace(
                  position: '2º',
                  room: '8ºB',
                  points: '920 pts',
                  height: 86,
                  color: AppColors.blue,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PodiumPlace(
                  position: '1º',
                  room: '7ºA',
                  points: '1.240 pts',
                  height: 112,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PodiumPlace(
                  position: '3º',
                  room: '6ºC',
                  points: '810 pts',
                  height: 72,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Sua turma está em 4º e faltam 50 pts para entrar no top 3.',
          ),
        ],
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
    return Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color,
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
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.42)),
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
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Row(
          children: [
            const CoinIcon(size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle),
                ],
              ),
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
          Container(
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

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.image, required this.label});

  final String image;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(
              image,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned(left: 10, top: 10, child: BadgeLabel(label: label)),
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

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
