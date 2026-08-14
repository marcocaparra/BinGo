import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

const userBinCoins = 120;

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
  restoredProgress: 0.68,
  nextSectorDiscards: 2,
  nextSectorName: 'Parque das Nascentes',
  cycleDays: 12,
);

enum ScenarioState { active, locked, completed }

enum ScenarioVisualPhase { corrupted, combat, restored }

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
    required this.landmarkIcon,
    required this.unlockRequirement,
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
  final IconData landmarkIcon;
  final String unlockRequirement;

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
  progressByScenario: {'central-square': 0.68},
);

const centralSquareScenario = CityScenario(
  id: 'central-square',
  order: 1,
  name: 'Praça Central',
  description:
      'O coração de BinGópolis e o primeiro cenário da jornada da sua turma.',
  progress: 0.68,
  state: ScenarioState.active,
  cleanAsset: AppAssets.sceneClean,
  corruptAsset: AppAssets.sceneCorrupt,
  combatAsset: AppAssets.sceneConfrontation,
  mapLandmarkAsset: AppAssets.mapLandmarkSquare,
  landmarkIcon: Icons.water_drop_rounded,
  unlockRequirement: 'Conclua a restauração da Praça Central.',
);

const cityScenarios = <CityScenario>[
  centralSquareScenario,
  CityScenario(
    id: 'spring-park',
    order: 2,
    name: 'Parque das Nascentes',
    description:
        'Trilhas, água e natureza aguardam a próxima onda de restauração.',
    progress: 0,
    state: ScenarioState.locked,
    cleanAsset: AppAssets.springParkClean,
    corruptAsset: AppAssets.springParkCorrupt,
    combatAsset: AppAssets.springParkCombat,
    mapLandmarkAsset: AppAssets.mapLandmarkPark,
    landmarkIcon: Icons.park_rounded,
    unlockRequirement: 'Restaure 100% da Praça Central.',
  ),
  CityScenario(
    id: 'creative-school',
    order: 3,
    name: 'Escola Criativa',
    description:
        'Um campus onde conhecimento, tecnologia e sustentabilidade se encontram.',
    progress: 0,
    state: ScenarioState.locked,
    cleanAsset: AppAssets.creativeSchoolClean,
    corruptAsset: AppAssets.creativeSchoolCorrupt,
    combatAsset: AppAssets.creativeSchoolCombat,
    mapLandmarkAsset: AppAssets.mapLandmarkSchool,
    landmarkIcon: Icons.school_rounded,
    unlockRequirement: 'Restaure 100% do Parque das Nascentes.',
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
  title: 'Recicle 1 item',
  subtitle: 'Leve um eletrônico pequeno ao Totem da escola.',
  detailTitle: 'Missão rápida',
  detailText: 'Uma ação simples para aumentar a recuperação de BinGópolis.',
  progress: 0.68,
  reward: '+10 BinCoins',
  color: AppColors.green,
  image: AppAssets.sceneClean,
  state: MissionState.active,
  steps: [
    ('Separe um item', 'Mouse, cabo, fone ou eletrônico pequeno.'),
    ('Vá ao Totem físico', 'No Totem, selecione sua turma.'),
    ('Descarte corretamente', 'Depois veja seus BinCoins no app.'),
  ],
);

const missions = [
  Mission(
    id: 'three-electronics',
    title: 'Recicle 3 eletrônicos',
    subtitle: '3 de 3 descartes concluídos',
    detailTitle: 'Combo eletrônico',
    detailText: 'Complete 3 descartes corretos para acelerar sua turma.',
    progress: 1,
    reward: '+30 BinCoins',
    color: AppColors.green,
    image: AppAssets.sceneClean,
    state: MissionState.completed,
    steps: [
      ('Confira o item', 'Separe eletrônicos pequenos e seguros.'),
      ('Registre no Totem', 'Selecione sua turma antes do descarte.'),
      ('Complete 3 descartes', 'O progresso aparece no app após validação.'),
    ],
  ),
  Mission(
    id: 'class-rank',
    title: 'Ajude sua turma',
    subtitle: 'Faltam 50 pts para subir uma posição',
    detailTitle: 'Virada da turma',
    detailText: 'Cada descarte correto soma pontos para sua sala.',
    progress: 0.45,
    reward: '+1 setor',
    color: AppColors.blue,
    image: AppAssets.sceneTransition,
    state: MissionState.upcoming,
    steps: [
      ('Veja a meta', 'Faltam 50 pontos para chegar ao 3º lugar.'),
      ('Some descartes', 'Combine com sua turma para levar itens ao Totem.'),
      ('Libere setor', 'Ao bater a meta, BinGópolis muda visualmente.'),
    ],
  ),
  Mission(
    id: 'scr4p-defense',
    title: 'Defesa contra SCR4P',
    subtitle: 'Ajude a turma com 5 descartes até sexta.',
    detailTitle: 'Defesa especial',
    detailText: 'SCR4P está avançando. A turma precisa reagir em conjunto.',
    progress: 0.58,
    reward: '+20 bônus',
    color: AppColors.scr4p,
    image: AppAssets.sceneCorruptScr4p,
    state: MissionState.event,
    steps: [
      ('Entre na defesa', 'Veja quantos descartes faltam no evento.'),
      ('Leve itens ao Totem', 'Todo descarte correto reduz a corrupção.'),
      (
        'Ganhe bônus',
        'Participantes recebem recompensa extra se a turma vencer.',
      ),
    ],
  ),
];

const rewards = [
  RewardItem(
    id: 'natural-juice',
    title: 'Suco natural',
    cost: 30,
    icon: Icons.local_drink,
    color: AppColors.green,
    asset: AppAssets.rewardJuice,
    description: 'Uma bebida natural para recarregar as energias.',
    pickupInstruction: 'Apresente o código no balcão da escola.',
  ),
  RewardItem(
    id: 'themed-pen',
    title: 'Caneta temática',
    cost: 70,
    icon: Icons.edit,
    color: AppColors.blue,
    asset: AppAssets.rewardPen,
    description: 'Caneta especial da jornada de restauração.',
    pickupInstruction: 'Apresente o código no balcão da escola.',
  ),
  RewardItem(
    id: 'cafeteria-ticket',
    title: 'Ticket cantina',
    cost: 120,
    icon: Icons.confirmation_number,
    color: AppColors.warning,
    asset: AppAssets.rewardCafeteriaTicket,
    description: 'Um ticket demonstrativo para usar na cantina.',
    pickupInstruction: 'Apresente o código no balcão da cantina.',
  ),
  RewardItem(
    id: 'surprise-reward',
    title: 'Prêmio surpresa',
    cost: 180,
    icon: Icons.card_giftcard,
    color: AppColors.scr4p,
    asset: AppAssets.rewardSurprise,
    description: 'Uma recompensa misteriosa para restauradores dedicados.',
    pickupInstruction: 'Apresente o código no balcão da escola.',
  ),
];

const binCoinTransactions = [
  BinCoinTransaction(
    title: 'Ganhou',
    subtitle: 'Missão rápida concluída',
    amount: 10,
    kind: TransactionKind.credit,
  ),
  BinCoinTransaction(
    title: 'Usou',
    subtitle: 'Suco natural resgatado no BinBazar',
    amount: 30,
    kind: TransactionKind.debit,
  ),
  BinCoinTransaction(
    title: 'Ganhou',
    subtitle: 'Bônus de setor liberado',
    amount: 20,
    kind: TransactionKind.credit,
  ),
];

const discardHistory = [
  DiscardRecord(
    item: 'Mouse sem uso',
    dateLabel: 'Hoje · 10:24',
    binCoins: 10,
    classPoints: 25,
    icon: Icons.mouse_outlined,
  ),
  DiscardRecord(
    item: 'Cabo USB',
    dateLabel: '25 jul · 14:10',
    binCoins: 8,
    classPoints: 20,
    icon: Icons.cable_outlined,
  ),
  DiscardRecord(
    item: 'Fone de ouvido',
    dateLabel: '22 jul · 09:42',
    binCoins: 12,
    classPoints: 30,
    icon: Icons.headphones_outlined,
  ),
];

const classRows = [
  ('1º', '7ºA', '1.240 pts', '+180'),
  ('2º', '8ºB', '920 pts', '+90'),
  ('3º', '6ºC', '810 pts', '+70'),
  ('4º', '9ºA', '760 pts', '+210 hoje'),
];

const impactImages = [AppAssets.sceneCorrupt, AppAssets.sceneClean];
