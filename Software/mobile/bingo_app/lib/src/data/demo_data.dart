import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

const userBinCoins = 120;

class ScenarioSnapshot {
  const ScenarioSnapshot({
    required this.name,
    required this.restoredProgress,
    required this.nextSectorDiscards,
    required this.cycleDays,
  });

  final String name;
  final double restoredProgress;
  final int nextSectorDiscards;
  final int cycleDays;

  int get restoredPercent => (restoredProgress * 100).round();
}

const currentScenario = ScenarioSnapshot(
  name: 'Praça Central',
  restoredProgress: 0.68,
  nextSectorDiscards: 2,
  cycleDays: 12,
);

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
    required this.title,
    required this.cost,
    required this.icon,
    required this.color,
  });

  final String title;
  final int cost;
  final IconData icon;
  final Color color;

  bool get available => userBinCoins >= cost;
  String get status =>
      available ? 'Ver no Totem' : 'Faltam ${cost - userBinCoins}';
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
    title: 'Suco natural',
    cost: 30,
    icon: Icons.local_drink,
    color: AppColors.green,
  ),
  RewardItem(
    title: 'Caneta temática',
    cost: 70,
    icon: Icons.edit,
    color: AppColors.blue,
  ),
  RewardItem(
    title: 'Ticket cantina',
    cost: 120,
    icon: Icons.confirmation_number,
    color: AppColors.warning,
  ),
  RewardItem(
    title: 'Prêmio surpresa',
    cost: 180,
    icon: Icons.card_giftcard,
    color: AppColors.danger,
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
    subtitle: 'Suco natural resgatado no Totem',
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
