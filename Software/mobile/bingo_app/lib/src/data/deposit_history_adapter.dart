import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'deposit_history_repository.dart';

class DepositHistoryAdapter {
  DepositHistoryAdapter({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DiscardRecord toDiscardRecord(AuthenticatedDepositHistoryEntry entry) {
    return DiscardRecord(
      item: entry.category?.displayName ?? entry.detectedType!,
      dateLabel: _formatDate(entry.createdAt),
      binCoins: entry.pointsAwardedStudent,
      classPoints: entry.pointsAwardedClass,
      icon: _iconFor(entry),
    );
  }

  String _formatDate(DateTime value) {
    final localValue = value.toLocal();
    final localNow = _now().toLocal();
    final time =
        '${_twoDigits(localValue.hour)}:'
        '${_twoDigits(localValue.minute)}';
    if (localValue.year == localNow.year &&
        localValue.month == localNow.month &&
        localValue.day == localNow.day) {
      return 'Hoje · $time';
    }
    final valueDay = DateTime(
      localValue.year,
      localValue.month,
      localValue.day,
    );
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    if (today.difference(valueDay).inDays == 1) {
      return 'Ontem · $time';
    }
    return '${localValue.day} ${_months[localValue.month - 1]} · $time';
  }

  IconData _iconFor(AuthenticatedDepositHistoryEntry entry) {
    return switch (entry.category?.code) {
      'BATTERY' => Icons.battery_charging_full_rounded,
      'MOBILE_DEVICE' => Icons.smartphone_rounded,
      'CABLE_WIRE' => Icons.cable_outlined,
      'PERIPHERAL' => Icons.mouse_outlined,
      'OTHER_EWASTE' => Icons.devices_other_rounded,
      'UNKNOWN' => Icons.recycling_rounded,
      _ => _iconForDetectedType(entry.detectedType),
    };
  }
}

IconData _iconForDetectedType(String? detectedType) {
  final normalized = detectedType?.toLowerCase() ?? '';
  if (normalized.contains('battery') ||
      normalized.contains('bateria') ||
      normalized.contains('pilha')) {
    return Icons.battery_charging_full_rounded;
  }
  if (normalized.contains('phone') ||
      normalized.contains('celular') ||
      normalized.contains('tablet')) {
    return Icons.smartphone_rounded;
  }
  if (normalized.contains('cable') ||
      normalized.contains('cabo') ||
      normalized.contains('wire') ||
      normalized.contains('fio')) {
    return Icons.cable_outlined;
  }
  if (normalized.contains('mouse') || normalized.contains('peripheral')) {
    return Icons.mouse_outlined;
  }
  if (normalized.contains('headphone') || normalized.contains('fone')) {
    return Icons.headphones_outlined;
  }
  return Icons.recycling_rounded;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];
