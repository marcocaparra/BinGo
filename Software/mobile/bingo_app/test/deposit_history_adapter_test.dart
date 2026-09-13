import 'package:bingo_app/src/data/deposit_history_adapter.dart';
import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'maps canonical category, date and persisted values for the frozen tile',
    () {
      final adapter = DepositHistoryAdapter(
        now: () => DateTime(2026, 9, 5, 15),
      );
      final record = adapter.toDiscardRecord(
        AuthenticatedDepositHistoryEntry(
          id: 'deposit-id',
          createdAt: DateTime(2026, 9, 5, 10, 24),
          isValid: true,
          detectedType: 'raw-battery',
          category: const DepositHistoryCategory(
            id: 'category-id',
            code: 'BATTERY',
            displayName: 'Pilha ou bateria',
          ),
          categorySource: 'AI_CONFIRMED',
          bonusBinCoinsAwarded: 23,
          pointsAwardedStudent: 137,
          pointsAwardedClass: 91,
        ),
      );

      expect(record.item, 'Pilha ou bateria');
      expect(record.dateLabel, 'Hoje · 10:24');
      expect(record.binCoins, 137);
      expect(record.classPoints, 91);
      expect(record.icon, Icons.battery_charging_full_rounded);
    },
  );

  test('uses detected_type as controlled title and icon fallback', () {
    final adapter = DepositHistoryAdapter(now: () => DateTime(2026, 9, 5));
    final record = adapter.toDiscardRecord(
      AuthenticatedDepositHistoryEntry(
        id: 'deposit-id',
        createdAt: DateTime(2026, 7, 25, 14, 10),
        isValid: true,
        detectedType: 'Cabo USB',
        category: null,
        categorySource: 'AI_CONFIRMED',
        bonusBinCoinsAwarded: 0,
        pointsAwardedStudent: 8,
        pointsAwardedClass: 19,
      ),
    );

    expect(record.item, 'Cabo USB');
    expect(record.dateLabel, '25 jul · 14:10');
    expect(record.icon, Icons.cable_outlined);
  });
}
