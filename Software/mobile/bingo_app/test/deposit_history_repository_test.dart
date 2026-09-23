import 'package:bingo_app/src/data/deposit_history_repository.dart';
import 'package:bingo_app/src/data/supabase_deposit_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeDepositHistoryDataSource implements DepositHistoryDataSource {
  _FakeDepositHistoryDataSource({
    this.hasSession = true,
    this.rows = const [],
    this.error,
  });

  @override
  final bool hasSession;
  final List<Map<String, dynamic>> rows;
  final Object? error;
  String? requestedStudentId;
  int? requestedLimit;

  @override
  Future<List<Map<String, dynamic>>> fetchValidDeposits({
    required String studentId,
    required int limit,
  }) async {
    requestedStudentId = studentId;
    requestedLimit = limit;
    if (error != null) throw error!;
    return rows;
  }
}

Map<String, dynamic> validRow({
  String id = 'deposit-id',
  String studentId = 'student-id',
  String createdAt = '2026-09-05T12:30:00Z',
  bool isValid = true,
  String? detectedType = 'battery',
  bool includeCategory = true,
  Object? pointsAwardedStudent = 137,
  Object? pointsAwardedClass = 91,
  Object? bonusBinCoinsAwarded = 23,
}) {
  return <String, dynamic>{
    'id': id,
    'student_id': studentId,
    'created_at': createdAt,
    'is_valid': isValid,
    'detected_type': detectedType,
    'waste_category_id': includeCategory ? 'category-id' : null,
    'category_source': isValid ? 'AI_CONFIRMED' : null,
    'bonus_bincoins_awarded': bonusBinCoinsAwarded,
    'points_awarded_student': pointsAwardedStudent,
    'points_awarded_class': pointsAwardedClass,
    'waste_categories': includeCategory
        ? <String, dynamic>{
            'id': 'category-id',
            'code': 'BATTERY',
            'display_name': 'Pilha ou bateria',
          }
        : null,
  };
}

void main() {
  test(
    'parses a valid row and preserves persisted scoring snapshots',
    () async {
      final dataSource = _FakeDepositHistoryDataSource(rows: [validRow()]);
      final repository = RemoteDepositHistoryRepository(dataSource);

      final history = await repository.loadHistory(studentId: 'student-id');

      expect(history, hasLength(1));
      expect(history.single.id, 'deposit-id');
      expect(history.single.createdAt, DateTime.parse('2026-09-05T12:30:00Z'));
      expect(history.single.category?.code, 'BATTERY');
      expect(history.single.category?.displayName, 'Pilha ou bateria');
      expect(history.single.bonusBinCoinsAwarded, 23);
      expect(history.single.pointsAwardedStudent, 137);
      expect(history.single.pointsAwardedClass, 91);
      expect(dataSource.requestedStudentId, 'student-id');
      expect(dataSource.requestedLimit, 20);
    },
  );

  test(
    'accepts an absent category when detected_type supports fallback',
    () async {
      final repository = RemoteDepositHistoryRepository(
        _FakeDepositHistoryDataSource(
          rows: [validRow(includeCategory: false, detectedType: 'Cabo USB')],
        ),
      );

      final history = await repository.loadHistory(studentId: 'student-id');

      expect(history.single.category, isNull);
      expect(history.single.detectedType, 'Cabo USB');
    },
  );

  test(
    'returns an empty immutable history without synthesizing rows',
    () async {
      final repository = RemoteDepositHistoryRepository(
        _FakeDepositHistoryDataSource(),
      );

      final history = await repository.loadHistory(studentId: 'student-id');

      expect(history, isEmpty);
      expect(() => history.add(_entryForMutationTest), throwsUnsupportedError);
    },
  );

  test('maps network failures without activating fallback data', () async {
    final repository = RemoteDepositHistoryRepository(
      _FakeDepositHistoryDataSource(
        error: Exception('SocketException: connection refused'),
      ),
    );

    await expectLater(
      repository.loadHistory(studentId: 'student-id'),
      throwsA(
        isA<DepositHistoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          DepositHistoryFailureKind.network,
        ),
      ),
    );
  });

  test(
    'preserves every PostgREST diagnostic field in the failure cause',
    () async {
      const postgrestError = PostgrestException(
        code: '42501',
        message: 'permission denied for table deposits',
        details: 'RLS or column grant rejected the query',
        hint: 'Check the authenticated grants',
      );
      final repository = RemoteDepositHistoryRepository(
        _FakeDepositHistoryDataSource(error: postgrestError),
      );

      try {
        await repository.loadHistory(studentId: 'student-id');
        fail('Expected DepositHistoryFailure.');
      } on DepositHistoryFailure catch (failure) {
        expect(failure.kind, DepositHistoryFailureKind.unknown);
        expect(failure.cause, same(postgrestError));
        final cause = failure.cause! as PostgrestException;
        expect(cause.code, '42501');
        expect(cause.message, 'permission denied for table deposits');
        expect(cause.details, 'RLS or column grant rejected the query');
        expect(cause.hint, 'Check the authenticated grants');
      }
    },
  );

  test('rejects loading without an authenticated session', () async {
    final repository = RemoteDepositHistoryRepository(
      _FakeDepositHistoryDataSource(hasSession: false),
    );

    await expectLater(
      repository.loadHistory(studentId: 'student-id'),
      throwsA(
        isA<DepositHistoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          DepositHistoryFailureKind.sessionInvalid,
        ),
      ),
    );
  });

  test('rejects malformed payload instead of recalculating it', () async {
    final repository = RemoteDepositHistoryRepository(
      _FakeDepositHistoryDataSource(
        rows: [validRow(pointsAwardedStudent: '137')],
      ),
    );

    await expectLater(
      repository.loadHistory(studentId: 'student-id'),
      throwsA(
        isA<DepositHistoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          DepositHistoryFailureKind.malformedData,
        ),
      ),
    );
  });

  test('rejects a validated row without category or detected type', () async {
    final repository = RemoteDepositHistoryRepository(
      _FakeDepositHistoryDataSource(
        rows: [validRow(includeCategory: false, detectedType: null)],
      ),
    );

    await expectLater(
      repository.loadHistory(studentId: 'student-id'),
      throwsA(isA<DepositHistoryFailure>()),
    );
  });

  test(
    'orders newest first even if the data source response is unordered',
    () async {
      final repository = RemoteDepositHistoryRepository(
        _FakeDepositHistoryDataSource(
          rows: [
            validRow(id: 'older', createdAt: '2026-09-01T10:00:00Z'),
            validRow(id: 'newest', createdAt: '2026-09-03T10:00:00Z'),
            validRow(id: 'middle', createdAt: '2026-09-02T10:00:00Z'),
          ],
        ),
      );

      final history = await repository.loadHistory(studentId: 'student-id');

      expect(history.map((entry) => entry.id), ['newest', 'middle', 'older']);
    },
  );

  test(
    'defensively excludes invalid deposits from displayed history',
    () async {
      final repository = RemoteDepositHistoryRepository(
        _FakeDepositHistoryDataSource(
          rows: [
            validRow(id: 'valid'),
            validRow(
              id: 'invalid',
              isValid: false,
              includeCategory: false,
              detectedType: null,
              pointsAwardedStudent: 0,
              pointsAwardedClass: 0,
              bonusBinCoinsAwarded: 0,
            ),
          ],
        ),
      );

      final history = await repository.loadHistory(studentId: 'student-id');

      expect(history.map((entry) => entry.id), ['valid']);
      expect(history.every((entry) => entry.isValid), isTrue);
    },
  );
}

final _entryForMutationTest = AuthenticatedDepositHistoryEntry(
  id: 'unused',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  isValid: true,
  detectedType: 'unused',
  category: null,
  categorySource: null,
  bonusBinCoinsAwarded: 0,
  pointsAwardedStudent: 0,
  pointsAwardedClass: 0,
);
