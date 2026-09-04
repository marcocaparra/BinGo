import 'package:bingo_app/src/data/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mission copy follows the environmental glossary', () {
    final missionCopy = <String>[
      activeMission.title,
      activeMission.subtitle,
      activeMission.detailText,
      for (final step in activeMission.steps) ...[step.$1, step.$2],
    ].join(' ').toLowerCase();

    expect(missionCopy, contains('descarte'));
    expect(missionCopy, contains('totem'));
    expect(missionCopy, contains('valida'));
    expect(missionCopy, isNot(contains('recicle')));
    expect(missionCopy, isNot(contains('compre')));
    expect(missionCopy, isNot(contains('quebre')));
  });

  test('reward copy identifies the local redemption simulation', () {
    for (final reward in rewards) {
      expect(reward.pickupInstruction.toLowerCase(), contains('simula'));
    }
  });
}
