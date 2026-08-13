import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_navigation_bar.dart';
import '../widgets/bingo_action_button.dart';
import '../widgets/bingo_widgets.dart';
import 'profile_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({this.initialIndex = 0, this.onExitPilot, super.key});

  final int initialIndex;
  final Future<void> Function()? onExitPilot;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(firstName: 'Marco', onOpenTab: _selectTab),
      const WalletScreen(),
      const MissionsScreen(),
      const RankingScreen(),
      ProfileScreen(
        onGoHome: () => _selectTab(0),
        onExitPilot: widget.onExitPilot,
      ),
    ];

    return Scaffold(
      body: Banner(
        message: 'MODO PILOTO',
        location: BannerLocation.topEnd,
        color: AppColors.blue,
        child: pages[_index],
      ),
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
      message: 'Leve um eletrônico seguro ao Totem.',
    );
    final cta = BingoActionButton(
      label: 'Começar no Totem',
      tone: BingoActionTone.green,
      icon: Icons.directions_walk,
      onPressed: () =>
          _push(context, const TotemTrackingScreen(mission: activeMission)),
    );
    final primaryFlow = usesLargeText
        ? <Widget>[
            prompt,
            const SizedBox(height: 8),
            cta,
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
      subtitle: 'Sua turma está recuperando a ${currentScenario.name}.',
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
      subtitle: 'Prepare o item e avance com segurança.',
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
          B1nDialogueStrip(message: mission.detailText, tone: mission.color),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Como completar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 14),
          _MissionTimeline(mission: mission),
          const SizedBox(height: 8),
          const _SafetyAlert(
            icon: Icons.health_and_safety_outlined,
            title: 'Segurança antes dos pontos',
            message:
                'Leve itens pequenos, secos e seguros. Em caso de bateria, peça ajuda a um adulto.',
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
      subtitle: 'O equipamento valida. O app acompanha.',
      child: Column(
        children: [
          _TotemHero(mission: mission),
          const SizedBox(height: 18),
          const B1nDialogueStrip(
            message: 'Escolha sua turma no Totem e siga a tela do equipamento.',
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Seu caminho no Totem',
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
    super.key,
  });

  final List<BinCoinTransaction> transactions;
  final List<DiscardRecord> discards;
  final bool isLoading;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletSection _section = WalletSection.transactions;

  @override
  Widget build(BuildContext context) {
    final redeemableRewards = rewards
        .where((reward) => reward.available)
        .length;
    final sectionTone = _section == WalletSection.transactions
        ? AppColors.green
        : AppColors.blue;

    return AppPage(
      title: 'Carteira',
      subtitle: 'Seu saldo e o histórico do ecossistema.',
      showBackButton: false,
      child: Column(
        children: [
          SurfaceCard(
            color: const Color(0xFFFFF4C7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Saldo disponível',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.navy,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BinCoinAmount(
                  value: userBinCoins,
                  size: 32,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(fontSize: 36),
                ),
                const SizedBox(height: 10),
                Text('$redeemableRewards recompensas no Totem'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          BingoActionButton(
            label: 'Abrir BinBazar',
            icon: Icons.storefront,
            onPressed: () => _push(context, const RewardsScreen()),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.25,
              child: SegmentedButton<WalletSection>(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    return states.contains(WidgetState.selected)
                        ? sectionTone.withValues(alpha: 0.14)
                        : Colors.transparent;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    return states.contains(WidgetState.selected)
                        ? sectionTone
                        : AppColors.navy;
                  }),
                  side: WidgetStateProperty.resolveWith((states) {
                    return BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? sectionTone
                          : AppColors.line,
                      width: states.contains(WidgetState.selected) ? 1.6 : 1,
                    );
                  }),
                ),
                segments: const [
                  ButtonSegment(
                    value: WalletSection.transactions,
                    label: Text('Extrato', maxLines: 1, softWrap: false),
                    icon: Icon(Icons.swap_vert_rounded),
                  ),
                  ButtonSegment(
                    value: WalletSection.discards,
                    label: Text('Descartes', maxLines: 1, softWrap: false),
                    icon: Icon(Icons.recycling_rounded),
                  ),
                ],
                selected: {_section},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.single);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.isLoading)
            const BingoDataState(
              kind: BingoDataStateKind.loading,
              title: 'Carregando histórico',
              message: 'Organizando as informações do Totem.',
            )
          else if (_section == WalletSection.transactions)
            if (widget.transactions.isEmpty)
              const BingoDataState(
                kind: BingoDataStateKind.empty,
                title: 'Nenhuma movimentação',
                message:
                    'Seus BinCoins aparecerão após uma validação no Totem.',
                icon: Icons.account_balance_wallet_outlined,
              )
            else
              for (final transaction in widget.transactions)
                _HistoryTile(transaction: transaction)
          else if (widget.discards.isEmpty)
            const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Nenhum descarte validado',
              message: 'Os descartes confirmados pelo Totem aparecerão aqui.',
              icon: Icons.recycling_outlined,
            )
          else
            for (final discard in widget.discards)
              _DiscardHistoryTile(discard: discard),
        ],
      ),
    );
  }
}

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({this.items = rewards, super.key});

  final List<RewardItem> items;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'BinBazar',
      subtitle: 'Consulte recompensas antes de ir ao Totem.',
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
                      const Text(
                        'O resgate e a retirada acontecem no Totem fisico.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'BinBazar sem recompensas',
              message:
                  'Novas opções aparecerão quando a escola atualizar o Totem.',
              icon: Icons.storefront_outlined,
            )
          else
            for (final reward in items) ...[
              _RewardTile(reward: reward),
              const SizedBox(height: 12),
            ],
        ],
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
      title: 'Missões',
      subtitle: 'Escolha seu próximo passo em BinGópolis.',
      showBackButton: false,
      child: items.isEmpty
          ? const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Nenhuma missão disponível',
              message:
                  'As próximas missões aparecerão depois da atualização do Totem.',
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
                    'Evento em destaque',
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
                    'Outras missões',
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
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '2',
                  title: 'A turma limpa setores',
                  text: 'Cada descarte validado recupera uma parte do cenário.',
                  color: AppColors.scr4p,
                ),
                _StepRow(
                  number: '3',
                  title: 'Quem ajuda mais ganha mais',
                  text:
                      'Eventos SCR4P dão bônus por participação e contribuição.',
                  color: AppColors.scr4p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          BingoActionButton(
            label: 'Ver defesa ativa',
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
  const RankingScreen({this.rows = classRows, super.key});

  final List<(String, String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Ranking da turma',
      subtitle: 'Veja quem está perto de recuperar mais setores.',
      showBackButton: false,
      child: rows.isEmpty
          ? const BingoDataState(
              kind: BingoDataStateKind.empty,
              title: 'Ranking ainda sem dados',
              message:
                  'A classificação aparecerá após as primeiras validações no Totem.',
              icon: Icons.emoji_events_outlined,
            )
          : Column(
              children: [
                const _RankingHero(),
                const SizedBox(height: 18),
                const _PodiumCard(),
                const SizedBox(height: 18),
                _ScenarioAccessCard(
                  onPressed: () =>
                      _push(context, const CurrentScenarioScreen()),
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
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return AppPage(
      title: 'Cenário atual',
      subtitle: 'Onde o ciclo do ranking está acontecendo.',
      child: Column(
        children: [
          const B1nDialogueStrip(
            message:
                'A Praça Central é o cenário deste ciclo: cada ponto da turma ajuda a recuperar um setor.',
          ),
          const SizedBox(height: 18),
          ImageHeroCard(
            image: AppAssets.sceneConfrontation,
            badge: currentScenario.name,
            title: '${currentScenario.restoredPercent}% restaurada',
            subtitle: 'Setores restaurados pela soma de pontos das turmas.',
            height: usesLargeText ? 384 : 220,
            progress: currentScenario.restoredProgress,
            progressColor: AppColors.green,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ScenarioMetric(
                  icon: Icons.recycling_rounded,
                  value: '${currentScenario.nextSectorDiscards}',
                  label: 'descartes para o setor',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScenarioMetric(
                  icon: Icons.schedule_rounded,
                  value: '${currentScenario.cycleDays}',
                  label: 'dias neste ciclo',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _RestorationScale(),
          const SizedBox(height: 18),
          const SurfaceCard(
            child: Column(
              children: [
                _ScenarioInfoLine(
                  icon: Icons.location_city_rounded,
                  title: 'Cenário',
                  text: 'É o lugar grande que o SCR4P está atacando agora.',
                  color: AppColors.scr4p,
                ),
                Divider(height: 24, color: AppColors.line),
                _ScenarioInfoLine(
                  icon: Icons.grid_view_rounded,
                  title: 'Setores',
                  text: 'São as partes recuperadas quando a turma descarta.',
                  color: AppColors.blue,
                ),
                Divider(height: 24, color: AppColors.line),
                _ScenarioInfoLine(
                  icon: Icons.restart_alt_rounded,
                  title: 'Ciclo',
                  text:
                      'Quando acaba, os pontos da turma reiniciam e os prêmios saem.',
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
            onPressed: () => _push(context, const ImpactScreen()),
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
          const ImpactComparison(
            beforeImage: AppAssets.sceneCorrupt,
            nowImage: AppAssets.sceneClean,
            beforeLabel: 'Antes',
            nowLabel: 'Depois',
            beforeFit: BoxFit.cover,
            nowFit: BoxFit.cover,
          ),
          const SizedBox(height: 18),
          const _ImpactHeadline(),
          const SizedBox(height: 18),
          const _ImpactMetricsGrid(),
          const SizedBox(height: 18),
          const _NextTransformationCard(),
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
      subtitle: 'Uma ação física, dois resultados no app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HowItWorksHero(),
          const SizedBox(height: 22),
          Text(
            'Do eletrônico ao resultado',
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
                'Bateria inchada, item quente, molhado ou quebrado deve ficar com um adulto responsável.',
            color: AppColors.warning,
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
                    BinCoinAmount(
                      value: reward.cost,
                      size: 18,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BingoActionButton(
            label: reward.status,
            icon: reward.available
                ? Icons.storefront_outlined
                : Icons.lock_outline,
            tone: reward.available
                ? BingoActionTone.green
                : BingoActionTone.blue,
            style: reward.available
                ? BingoActionStyle.primary
                : BingoActionStyle.secondary,
            onPressed: reward.available
                ? () => _showSnack(
                    context,
                    'Consulte ${reward.title} com o Tio B3N no Totem.',
                  )
                : null,
          ),
        ],
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
          'Do eletrônico ao impacto. O Totem recebe o item e o app mostra o resultado.',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: usesLargeText ? 470 : 310),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    AppAssets.sceneTransition,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Positioned(
                  top: 20,
                  right: -46,
                  width: 210,
                  height: 220,
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.72,
                      alignment: Alignment.centerRight,
                      child: Image.asset(
                        AppAssets.totemConceptFull,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerRight,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
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
                          AppColors.navy.withValues(alpha: 0.18),
                          AppColors.navy.withValues(alpha: 0.96),
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -8,
                  top: 22,
                  width: 138,
                  height: 170,
                  child: Image.asset(
                    AppAssets.b1nIdeaInstruction,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    minHeight: usesLargeText ? 470 : 310,
                  ),
                  width: double.infinity,
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BadgeLabel(
                          label: 'Totem + app',
                          color: AppColors.blue,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Do eletrônico ao impacto',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'O app orienta; o descarte acontece no Totem e o resultado aparece aqui.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
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
          text: 'Separe um eletrônico pequeno, sem uso, seco e autorizado.',
          color: AppColors.green,
        ),
        _HowItWorksStep(
          number: 2,
          icon: Icons.precision_manufacturing_outlined,
          title: 'Use o Totem',
          text: 'Escolha sua turma e siga as instruções do equipamento físico.',
          color: AppColors.blue,
        ),
        _HowItWorksStep(
          number: 3,
          icon: Icons.phone_android_outlined,
          title: 'Acompanhe no app',
          text:
              'Depois da validação, consulte BinCoins, pontos e a recuperação da cidade.',
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
              text: 'BinCoins entram na sua Carteira.',
              color: AppColors.blue,
            ),
          ),
          const Expanded(
            child: _HowItWorksOutcome(
              icon: Icons.groups_2_outlined,
              title: 'Resultado coletivo',
              text: 'Pontos recuperam setores da cidade.',
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
                text: 'BinCoins entram na sua Carteira.',
                color: AppColors.blue,
              ),
              SizedBox(height: 10),
              _HowItWorksOutcome(
                icon: Icons.groups_2_outlined,
                title: 'Resultado coletivo',
                text: 'Pontos recuperam setores da cidade.',
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

class _CharacterPortrait extends StatelessWidget {
  const _CharacterPortrait({
    required this.asset,
    required this.tone,
    required this.width,
    required this.height,
  });

  final String asset;
  final Color tone;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.high,
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
    return Semantics(
      button: true,
      label:
          'Missão ativa. ${mission.title}. ${mission.subtitle}. '
          'Recompensa ${mission.reward}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: AppColors.navy,
          child: InkWell(
            onTap: onTap,
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
                          AppColors.navy.withValues(alpha: 0.10),
                          AppColors.navy.withValues(alpha: 0.64),
                          AppColors.navy.withValues(alpha: 0.94),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 14,
                  right: 14,
                  child: _CharacterPortrait(
                    asset: AppAssets.b1nMissionReady,
                    tone: AppColors.green,
                    width: 82,
                    height: 98,
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    minHeight: usesLargeText ? 350 : 250,
                  ),
                  padding: const EdgeInsets.all(18),
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BadgeLabel(
                          label: 'Missão ativa',
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 5),
                      Text(
                        mission.subtitle,
                        maxLines: usesLargeText ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedProgressPill(
                        value: mission.progress,
                        color: AppColors.green,
                        backgroundColor: Colors.white.withValues(alpha: 0.72),
                        height: 10,
                      ),
                      const SizedBox(height: 12),
                      _MissionRewardBadge(mission: mission),
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

class _MissionEventBanner extends StatelessWidget {
  const _MissionEventBanner({required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Evento. ${mission.title}. ${mission.subtitle}. '
          'Recompensa ${mission.reward}.',
      child: Material(
        color: const Color(0xFFFBF8FF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: mission.color.withValues(alpha: 0.30),
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CharacterPortrait(
                  asset: AppAssets.scr4pDefense,
                  tone: AppColors.scr4p,
                  width: 66,
                  height: 78,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EVENTO ATIVO',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: mission.color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mission.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(mission.subtitle),
                      const SizedBox(height: 10),
                      AnimatedProgressPill(
                        value: mission.progress,
                        color: mission.color,
                        height: 9,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mission.reward,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: mission.color,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: mission.color),
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
    final stateLabel = isCompleted ? 'Concluída' : 'Em breve';

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
                  'SCR4P ainda controla 58% do setor',
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
            'Faltam 3 descartes validados para liberar o bônus do evento.',
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
          'Sua turma, 9ºA, está em quarto lugar com 760 pontos. '
          'Faltam 50 pontos para o top 3.',
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
                      'Faltam 50 pts para entrar no top 3',
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
                value: 760 / 810,
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
          '760 pts',
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
            'Top 3 e participação segura recebem bônus ao fim do ciclo.',
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
              height: 112,
              width: double.infinity,
              child: Image.asset(
                AppAssets.sceneConfrontation,
                fit: BoxFit.cover,
                alignment: Alignment.center,
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
                        'Cenário atual · ${currentScenario.name}',
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
                  '${currentScenario.restoredPercent}% restaurada · '
                  '${currentScenario.nextSectorDiscards} descartes para o '
                  'próximo setor',
                ),
                const SizedBox(height: 12),
                AnimatedProgressPill(
                  value: currentScenario.restoredProgress,
                  color: AppColors.green,
                ),
                const SizedBox(height: 14),
                BingoActionButton(
                  label: 'Ver cenário atual',
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
  const _RestorationScale();

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
                '${currentScenario.restoredPercent}%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final markerX =
                  (constraints.maxWidth - 18) *
                  currentScenario.restoredProgress;
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
  const _ImpactHeadline();

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
                  '${currentScenario.restoredPercent}% restaurada',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Sua turma está transformando a ${currentScenario.name}.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactMetricsGrid extends StatelessWidget {
  const _ImpactMetricsGrid();

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
              value: '3,2 kg',
              label: 'fora do lixo comum',
              color: AppColors.green,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.recycling_rounded,
              value: '8',
              label: 'descartes validados',
              color: AppColors.blue,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.groups_2_rounded,
              value: '12',
              label: 'alunos ativos',
              color: AppColors.warning,
            ),
            _ImpactMetric(
              width: itemWidth,
              icon: Icons.flag_rounded,
              value: '${currentScenario.nextSectorDiscards}',
              label: 'para o próximo setor',
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
  const _NextTransformationCard();

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
                    AppAssets.sceneTransition,
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
                  'Um novo setor está perto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  'Faltam ${currentScenario.nextSectorDiscards} descartes '
                  'validados no Totem para a cidade mudar novamente.',
                ),
                const SizedBox(height: 14),
                AnimatedProgressPill(
                  value: currentScenario.restoredProgress,
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
          'Totem físico do BinGo. Missão ${mission.title}. O equipamento valida o descarte.',
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
                            'O Totem confirma o descarte',
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
          title: 'Item preparado',
          text: 'Eletrônico sem uso, autorizado, seco e sem risco.',
          state: TotemStepState.ready,
        ),
        _TotemProcessStep(
          number: 2,
          title: 'Use o Totem',
          text: 'Escolha sua turma e siga a tela do equipamento.',
          state: TotemStepState.current,
        ),
        _TotemProcessStep(
          number: 3,
          title: 'Resultado no app',
          text: 'Após o Totem validar, BinCoins e pontos aparecem no app.',
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
              'Use somente item sem uso e autorizado. Nunca compre, quebre ou pegue algo de outra pessoa para ganhar pontos.',
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
            text: 'Cabos, mouse, fone, controle pequeno e acessórios secos.',
            color: AppColors.green,
          ),
          Divider(height: 24, color: AppColors.line),
          _TotemSafetyRow(
            icon: Icons.supervisor_account_outlined,
            title: 'Peça ajuda',
            text:
                'Celular, bateria solta, item trincado ou peça com ponta exposta.',
            color: AppColors.warning,
          ),
          Divider(height: 24, color: AppColors.line),
          _TotemSafetyRow(
            icon: Icons.dangerous_outlined,
            title: 'Não toque',
            text: 'Bateria inchada, vazando, molhada ou quente.',
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
          'Depois da validação. BinCoins aparecem na Carteira. '
          'Pontos e recuperação aparecem no Impacto.',
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
                'O Totem envia os resultados e o app atualiza as áreas de consulta.',
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
                text: 'Pontos e recuperação da turma',
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
                  'Missão ativa',
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

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
