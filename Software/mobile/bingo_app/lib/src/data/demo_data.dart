import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

const userBinCoins = 120;

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
  String get status => available ? 'Reservar' : 'Faltam ${cost - userBinCoins}';
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
    subtitle: '2 de 3 descartes concluídos',
    detailTitle: 'Combo eletrônico',
    detailText: 'Complete 3 descartes corretos para acelerar sua turma.',
    progress: 0.66,
    reward: '+30 BinCoins',
    color: AppColors.green,
    image: AppAssets.sceneClean,
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
    steps: [
      ('Veja a meta', 'Faltam 50 pontos para chegar ao 3º lugar.'),
      ('Some descartes', 'Combine com sua turma para levar itens ao Totem.'),
      ('Libere setor', 'Ao bater a meta, BinGópolis muda visualmente.'),
    ],
  ),
  Mission(
    id: 'scr4p-defense',
    title: 'Defesa contra SCR4P',
    subtitle: 'Evento de turma até sexta',
    detailTitle: 'Defesa especial',
    detailText: 'SCR4P está avançando. A turma precisa reagir em conjunto.',
    progress: 0.58,
    reward: '+20 bônus',
    color: AppColors.scr4p,
    image: AppAssets.sceneCorruptScr4p,
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

const classRows = [
  ('1º', '7ºA', '1.240 pts', '+180'),
  ('2º', '8ºB', '920 pts', '+90'),
  ('3º', '6ºC', '810 pts', '+70'),
  ('4º', '9ºA', '760 pts', '+210 hoje'),
];

const impactImages = [AppAssets.sceneCorrupt, AppAssets.sceneClean];
