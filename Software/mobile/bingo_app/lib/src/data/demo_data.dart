import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

const userBinCoins = 12000;
const centralSquareProgress = 0.68;

class ScenarioSnapshot {
  const ScenarioSnapshot({
    required this.name,
    required this.restoredProgress,
    required this.nextSectorDiscards,
    required this.nextSectorName,
    required this.cycleDays,
  });

  final String name;
  final double restoredProgress;
  final int nextSectorDiscards;
  final String nextSectorName;
  final int cycleDays;

  int get restoredPercent => (restoredProgress * 100).round();
}

const currentScenario = ScenarioSnapshot(
  name: 'Praça Central',
  restoredProgress: centralSquareProgress,
  nextSectorDiscards: 2,
  nextSectorName: 'Parque das Nascentes',
  cycleDays: 12,
);

enum ScenarioState { active, locked, completed }

enum ScenarioVisualPhase { corrupted, combat, restored }

class ScenarioImpactSnapshot {
  const ScenarioImpactSnapshot({
    required this.recoveredWeightKg,
    required this.validatedDiscards,
    required this.activeStudents,
    required this.remainingDiscards,
    required this.nextGoal,
  });

  final double recoveredWeightKg;
  final int validatedDiscards;
  final int activeStudents;
  final int remainingDiscards;
  final String nextGoal;
}

class CityScenario {
  const CityScenario({
    required this.id,
    required this.order,
    required this.name,
    required this.description,
    required this.progress,
    required this.state,
    required this.cleanAsset,
    required this.corruptAsset,
    required this.combatAsset,
    required this.mapLandmarkAsset,
    required this.corruptMapLandmarkAsset,
    required this.landmarkIcon,
    required this.unlockRequirement,
    required this.impact,
  });

  final String id;
  final int order;
  final String name;
  final String description;
  final double progress;
  final ScenarioState state;
  final String cleanAsset;
  final String corruptAsset;
  final String combatAsset;
  final String mapLandmarkAsset;
  final String corruptMapLandmarkAsset;
  final IconData landmarkIcon;
  final String unlockRequirement;
  final ScenarioImpactSnapshot impact;

  int get restoredPercent => (progress * 100).round();
  double get corruption => 1 - progress;

  ScenarioVisualPhase phaseFor(double value) {
    if (value < 0.35) return ScenarioVisualPhase.corrupted;
    if (value < 0.85) return ScenarioVisualPhase.combat;
    return ScenarioVisualPhase.restored;
  }

  String assetFor(double value) => switch (phaseFor(value)) {
    ScenarioVisualPhase.corrupted => corruptAsset,
    ScenarioVisualPhase.combat => combatAsset,
    ScenarioVisualPhase.restored => cleanAsset,
  };
}

class DemoCampaignState {
  const DemoCampaignState({
    required this.activeScenarioId,
    required this.progressByScenario,
  });

  final String activeScenarioId;
  final Map<String, double> progressByScenario;

  double progressFor(CityScenario scenario) =>
      progressByScenario[scenario.id] ?? scenario.progress;
}

const demoCampaign = DemoCampaignState(
  activeScenarioId: 'central-square',
  progressByScenario: {'central-square': centralSquareProgress},
);

const centralSquareScenario = CityScenario(
  id: 'central-square',
  order: 1,
  name: 'Praça Central',
  description:
      'O coração de BinGópolis e o primeiro setor da jornada da sua turma.',
  progress: centralSquareProgress,
  state: ScenarioState.active,
  cleanAsset: AppAssets.sceneClean,
  corruptAsset: AppAssets.sceneCorrupt,
  combatAsset: AppAssets.sceneConfrontation,
  mapLandmarkAsset: AppAssets.mapLandmarkSquareV2,
  corruptMapLandmarkAsset: AppAssets.mapLandmarkSquareCorruptV3,
  landmarkIcon: Icons.water_drop_rounded,
  unlockRequirement: 'Conclua a restauração da Praça Central.',
  impact: ScenarioImpactSnapshot(
    recoveredWeightKg: 3.2,
    validatedDiscards: 8,
    activeStudents: 12,
    remainingDiscards: 2,
    nextGoal: 'Liberar o caminho para o Parque das Nascentes.',
  ),
);

const cityScenarios = <CityScenario>[
  centralSquareScenario,
  CityScenario(
    id: 'spring-park',
    order: 2,
    name: 'Parque das Nascentes',
    description:
        'Trilhas, água e natureza aguardam a próxima etapa da restauração.',
    progress: 0,
    state: ScenarioState.locked,
    cleanAsset: AppAssets.springParkClean,
    corruptAsset: AppAssets.springParkCorrupt,
    combatAsset: AppAssets.springParkCombat,
    mapLandmarkAsset: AppAssets.mapLandmarkParkV2,
    corruptMapLandmarkAsset: AppAssets.mapLandmarkParkCorruptV3,
    landmarkIcon: Icons.park_rounded,
    unlockRequirement: 'Restaure 100% da Praça Central.',
    impact: ScenarioImpactSnapshot(
      recoveredWeightKg: 0,
      validatedDiscards: 0,
      activeStudents: 0,
      remainingDiscards: 1,
      nextGoal: 'Validar o primeiro descarte do Parque.',
    ),
  ),
  CityScenario(
    id: 'creative-school',
    order: 3,
    name: 'Escola Criativa',
    description:
        'Um lugar onde conhecimento, tecnologia e escolhas conscientes se encontram.',
    progress: 0,
    state: ScenarioState.locked,
    cleanAsset: AppAssets.creativeSchoolClean,
    corruptAsset: AppAssets.creativeSchoolCorrupt,
    combatAsset: AppAssets.creativeSchoolCombat,
    mapLandmarkAsset: AppAssets.mapLandmarkSchoolV2,
    corruptMapLandmarkAsset: AppAssets.mapLandmarkSchoolCorruptV3,
    landmarkIcon: Icons.school_rounded,
    unlockRequirement: 'Restaure 100% do Parque das Nascentes.',
    impact: ScenarioImpactSnapshot(
      recoveredWeightKg: 0,
      validatedDiscards: 0,
      activeStudents: 0,
      remainingDiscards: 1,
      nextGoal: 'Validar o primeiro descarte da Escola.',
    ),
  ),
];

enum TransactionKind { credit, debit }

class BinCoinTransaction {
  const BinCoinTransaction({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
  });

  final String title;
  final String subtitle;
  final int amount;
  final TransactionKind kind;
}

class DiscardRecord {
  const DiscardRecord({
    required this.item,
    required this.dateLabel,
    required this.binCoins,
    required this.classPoints,
    required this.icon,
  });

  final String item;
  final String dateLabel;
  final int binCoins;
  final int classPoints;
  final IconData icon;
}

enum MissionState { active, event, completed, upcoming }

class Mission {
  const Mission({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.detailTitle,
    required this.detailText,
    required this.progress,
    required this.reward,
    required this.color,
    required this.image,
    required this.steps,
    required this.state,
  });

  final String id;
  final String title;
  final String subtitle;
  final String detailTitle;
  final String detailText;
  final double progress;
  final String reward;
  final Color color;
  final String image;
  final List<(String, String)> steps;
  final MissionState state;
}

class RewardItem {
  const RewardItem({
    required this.id,
    required this.title,
    required this.cost,
    required this.icon,
    required this.color,
    required this.asset,
    required this.description,
    required this.pickupInstruction,
  });

  final String id;
  final String title;
  final int cost;
  final IconData icon;
  final Color color;
  final String asset;
  final String description;
  final String pickupInstruction;

  bool isAvailable(int balance) => balance >= cost;
  String statusFor(int balance) =>
      isAvailable(balance) ? 'Disponível agora' : 'Faltam ${cost - balance}';
}

class RewardRedemption {
  const RewardRedemption({
    required this.id,
    required this.rewardId,
    required this.rewardTitle,
    required this.cost,
    required this.pickupCode,
    required this.createdAt,
  });

  final String id;
  final String rewardId;
  final String rewardTitle;
  final int cost;
  final String pickupCode;
  final DateTime createdAt;
}

const activeMission = Mission(
  id: 'quick-recycle',
  title: 'Descarte corretamente 1 eletrônico',
  subtitle: 'Separe um eletrônico sem uso e leve ao Totem.',
  detailTitle: 'Descarte consciente',
  detailText:
      'Um descarte seguro e validado ajuda sua turma a restaurar BinGópolis.',
  progress: 0.68,
  reward: '+1000 BinCoins',
  color: AppColors.green,
  image: AppAssets.sceneClean,
  state: MissionState.active,
  steps: [
    (
      'Separe com segurança',
      'Escolha um eletrônico sem uso, seco e autorizado.',
    ),
    ('Use o Totem', 'Identifique sua turma e siga as orientações da tela.'),
    (
      'Acompanhe o resultado',
      'Depois da validação, veja BinCoins e pontos no app.',
    ),
  ],
);

const missions = [
  Mission(
    id: 'three-electronics',
    title: 'Complete 3 descartes conscientes',
    subtitle: '3 de 3 descartes validados',
    detailTitle: 'Três escolhas que contam',
    detailText: 'Três descartes seguros ajudaram o progresso da sua turma.',
    progress: 1,
    reward: '+3000 BinCoins',
    color: AppColors.green,
    image: AppAssets.sceneClean,
    state: MissionState.completed,
    steps: [
      ('Confira cada item', 'Use somente eletrônicos sem uso e seguros.'),
      ('Valide no Totem', 'Identifique sua turma antes de cada descarte.'),
      ('Veja o progresso', 'O resultado aparece no app após a validação.'),
    ],
  ),
  Mission(
    id: 'class-rank',
    title: 'Avance com sua turma',
    subtitle: 'Faltam 5000 pontos para subir uma posição',
    detailTitle: 'Rumo ao pódio',
    detailText: 'Cada descarte validado soma pontos para a turma.',
    progress: 0.45,
    reward: '+1 setor',
    color: AppColors.blue,
    image: AppAssets.sceneTransition,
    state: MissionState.upcoming,
    steps: [
      ('Veja a meta', 'Faltam 5000 pontos para chegar ao 3º lugar.'),
      ('Participe com a turma', 'Cada descarte seguro e validado soma pontos.'),
      ('Abra um novo caminho', 'Ao atingir a meta, BinGópolis avança.'),
    ],
  ),
  Mission(
    id: 'scr4p-defense',
    title: 'Defesa contra SCR4P',
    subtitle: '5 descartes validados até sexta.',
    detailTitle: 'Força-tarefa SCR4P',
    detailText:
        'A corrupção ainda ocupa o setor. Sua turma pode recuperar este lugar em conjunto.',
    progress: 0.58,
    reward: '+20 bônus',
    color: AppColors.scr4p,
    image: AppAssets.sceneCorruptScr4p,
    state: MissionState.event,
    steps: [
      ('Veja a meta coletiva', 'Confira quantos descartes ainda faltam.'),
      (
        'Descarte com segurança',
        'Cada validação ajuda a turma a reduzir a corrupção.',
      ),
      (
        'Desbloqueie o bônus',
        'Participantes elegíveis recebem o bônus se a turma concluir a meta.',
      ),
    ],
  ),
];

const rewards = [
  RewardItem(
    id: 'natural-juice',
    title: 'Suco natural',
    cost: 3000,
    icon: Icons.local_drink,
    color: AppColors.green,
    asset: AppAssets.rewardJuice,
    description: 'Uma opção demonstrativa de bebida natural.',
    pickupInstruction: 'Na simulação, apresente o código no balcão da escola.',
  ),
  RewardItem(
    id: 'themed-pen',
    title: 'Caneta temática',
    cost: 7000,
    icon: Icons.edit,
    color: AppColors.blue,
    asset: AppAssets.rewardPen,
    description: 'Uma caneta temática da jornada de restauração.',
    pickupInstruction: 'Na simulação, apresente o código no balcão da escola.',
  ),
  RewardItem(
    id: 'cafeteria-ticket',
    title: 'Ticket cantina',
    cost: 12000,
    icon: Icons.confirmation_number,
    color: AppColors.warning,
    asset: AppAssets.rewardCafeteriaTicket,
    description: 'Um exemplo de ticket para a cantina.',
    pickupInstruction: 'Na simulação, apresente o código no balcão da cantina.',
  ),
  RewardItem(
    id: 'surprise-reward',
    title: 'Prêmio surpresa',
    cost: 18000,
    icon: Icons.card_giftcard,
    color: AppColors.scr4p,
    asset: AppAssets.rewardSurprise,
    description: 'Uma opção surpresa da jornada de restauração.',
    pickupInstruction: 'Na simulação, apresente o código no balcão da escola.',
  ),
];

const binCoinTransactions = [
  BinCoinTransaction(
    title: 'Crédito',
    subtitle: 'Missão de descarte consciente concluída',
    amount: 1000,
    kind: TransactionKind.credit,
  ),
  BinCoinTransaction(
    title: 'Uso',
    subtitle: 'Simulação: suco natural no BinBazar',
    amount: 3000,
    kind: TransactionKind.debit,
  ),
  BinCoinTransaction(
    title: 'Crédito',
    subtitle: 'Bônus de progresso territorial',
    amount: 2000,
    kind: TransactionKind.credit,
  ),
];

const discardHistory = [
  DiscardRecord(
    item: 'Mouse sem uso',
    dateLabel: 'Hoje · 10:24',
    binCoins: 1000,
    classPoints: 2500,
    icon: Icons.mouse_outlined,
  ),
  DiscardRecord(
    item: 'Cabo USB',
    dateLabel: '25 jul · 14:10',
    binCoins: 800,
    classPoints: 2000,
    icon: Icons.cable_outlined,
  ),
  DiscardRecord(
    item: 'Fone de ouvido',
    dateLabel: '22 jul · 09:42',
    binCoins: 1200,
    classPoints: 3000,
    icon: Icons.headphones_outlined,
  ),
];

const classRows = [
  ('1º', '7ºA', '124.000 pts', '+18.000'),
  ('2º', '8ºB', '92.000 pts', '+9.000'),
  ('3º', '6ºC', '81.000 pts', '+7.000'),
  ('4º', '9ºA', '76.000 pts', '+21.000 hoje'),
];

const impactImages = [AppAssets.sceneCorrupt, AppAssets.sceneClean];
