import 'package:bingo_app/src/data/class_journey_repository.dart';
import 'package:bingo_app/src/data/supabase_class_journey_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeDataSource implements ClassJourneyDataSource {
  _FakeDataSource({required this.rows, this.hasSession = true});

  final List<Map<String, dynamic>> rows;

  @override
  final bool hasSession;

  var calls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchJourney() async {
    calls++;
    return rows;
  }
}

List<Map<String, dynamic>> _rowsFor(int totalUnits) {
  const codes = ['CENTRAL_SQUARE', 'SPRING_PARK', 'CREATIVE_SCHOOL'];
  const targets = [20, 25, 30];
  var prior = 0;
  return List.generate(3, (index) {
    final progress = (totalUnits - prior).clamp(0, targets[index]);
    final state = progress >= targets[index]
        ? 'COMPLETED'
        : totalUnits >= prior
        ? 'ACTIVE'
        : 'LOCKED';
    final row = <String, dynamic>{
      'campaign_id': 'campaign-id',
      'starts_at': '2026-07-01T03:00:00Z',
      'ends_at': '2027-01-01T03:00:00Z',
      'stage_code': codes[index],
      'stage_order': index + 1,
      'target_units': targets[index],
      'progress_units': progress,
      'progress_ratio': (progress / targets[index]).toString(),
      'state': state,
      'total_units': totalUnits,
      'valid_deposit_count': 19,
      'student_mission_completion_count': 1,
      'class_mission_completion_count': 1,
      'remaining_units': targets[index] - progress,
    };
    prior += targets[index];
    return row;
  });
}

void main() {
  test('Supabase source calls get_class_journey_v1 without params', () async {
    String? calledFunction;
    var calls = 0;
    final source = SupabaseClassJourneyDataSource(
      SupabaseClient('https://example.test', 'test-publishable-key'),
      rpcInvoker: (functionName) async {
        calledFunction = functionName;
        calls++;
        return <Map<String, dynamic>>[];
      },
    );

    expect(await source.fetchJourney(), isEmpty);
    expect(calledFunction, 'get_class_journey_v1');
    expect(calls, 1);
  });

  test(
    'maps one validated snapshot with carry-over and scenario ids',
    () async {
      final source = _FakeDataSource(rows: _rowsFor(27));
      final repository = RemoteClassJourneyRepository(source);

      final journey = await repository.loadJourney();

      expect(source.calls, 1);
      expect(journey, isNotNull);
      expect(journey!.totalUnits, 27);
      expect(journey.validDepositCount, 19);
      expect(journey.studentMissionCompletionCount, 1);
      expect(journey.classMissionCompletionCount, 1);
      expect(journey.stages.map((stage) => stage.scenarioId), [
        'central-square',
        'spring-park',
        'creative-school',
      ]);
      expect(journey.stages[0].state, JourneyStageState.completed);
      expect(journey.currentStage.code, JourneyStageCode.springPark);
      expect(journey.currentStage.progressUnits, 7);
      expect(journey.currentStage.progressRatio, closeTo(0.28, 0.000001));
      expect(journey.currentStage.remainingUnits, 18);
    },
  );

  test(
    'returns null for an authenticated context without active journey',
    () async {
      final source = _FakeDataSource(rows: const []);
      final repository = RemoteClassJourneyRepository(source);

      expect(await repository.loadJourney(), isNull);
      expect(source.calls, 1);
    },
  );

  test('does not call RPC without a valid session', () async {
    final source = _FakeDataSource(rows: _rowsFor(0), hasSession: false);
    final repository = RemoteClassJourneyRepository(source);

    await expectLater(
      repository.loadJourney(),
      throwsA(
        isA<JourneyFailure>().having(
          (failure) => failure.kind,
          'kind',
          JourneyFailureKind.sessionInvalid,
        ),
      ),
    );
    expect(source.calls, 0);
  });

  test('rejects missing stages instead of falling back to demo data', () async {
    final source = _FakeDataSource(rows: _rowsFor(27).take(2).toList());
    final repository = RemoteClassJourneyRepository(source);

    await expectLater(
      repository.loadJourney(),
      throwsA(
        isA<JourneyFailure>().having(
          (failure) => failure.kind,
          'kind',
          JourneyFailureKind.malformedData,
        ),
      ),
    );
  });

  test('rejects a server state inconsistent with total units', () async {
    final rows = _rowsFor(20);
    rows[1]['state'] = 'LOCKED';
    final repository = RemoteClassJourneyRepository(
      _FakeDataSource(rows: rows),
    );

    await expectLater(
      repository.loadJourney(),
      throwsA(
        isA<JourneyFailure>().having(
          (failure) => failure.kind,
          'kind',
          JourneyFailureKind.malformedData,
        ),
      ),
    );
  });

  test('total at or above 75 leaves all three stages completed', () async {
    final repository = RemoteClassJourneyRepository(
      _FakeDataSource(rows: _rowsFor(90)),
    );

    final journey = await repository.loadJourney();

    expect(journey!.stages, hasLength(3));
    expect(
      journey.stages.every(
        (stage) => stage.state == JourneyStageState.completed,
      ),
      isTrue,
    );
    expect(journey.currentStage.code, JourneyStageCode.creativeSchool);
  });
}
