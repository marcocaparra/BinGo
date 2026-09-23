import 'dart:convert';
import 'dart:io';

import 'package:bingo_app/src/auth/supabase_auth_gateway.dart';
import 'package:bingo_app/src/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _hostedSmokeEnabled = Platform.environment['BINGO_HOSTED_SMOKE'] == '1';

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Variável obrigatória ausente: $name');
  }
  return value;
}

({int level, String code, int remaining, double progress}) _expectedProgress(
  int count,
) {
  if (count >= 50) {
    return (level: 5, code: 'HERO', remaining: 0, progress: 1);
  }
  if (count >= 20) {
    return (
      level: 4,
      code: 'GUARDIAN',
      remaining: 50 - count,
      progress: count / 50,
    );
  }
  if (count >= 10) {
    return (
      level: 3,
      code: 'RESTORER',
      remaining: 20 - count,
      progress: count / 20,
    );
  }
  if (count >= 5) {
    return (
      level: 2,
      code: 'EXPLORER',
      remaining: 10 - count,
      progress: count / 10,
    );
  }
  if (count >= 1) {
    return (
      level: 1,
      code: 'APPRENTICE',
      remaining: 5 - count,
      progress: count / 5,
    );
  }
  return (level: 0, code: 'NONE', remaining: 1, progress: 0);
}

String _journeyMessage(AuthenticatedProfileProgress progress) {
  if (progress.levelNumber == 0) {
    return 'Faça seu primeiro descarte válido para chegar a Aprendiz.';
  }
  if (progress.levelNumber == 5) {
    return 'Você já fez ${progress.validDepositCount} descartes válidos e '
        'alcançou o nível Herói.';
  }
  return 'Você já fez ${progress.validDepositCount} descartes válidos. '
      'Faltam ${progress.remainingToNextLevel} para chegar a '
      '${progress.nextLevelName}.';
}

void main() {
  test(
    'smoke hospedado Auth, Trilha, isolamento e logout',
    () async {
      final url = _requiredEnvironment('SUPABASE_URL');
      final publishableKey = _requiredEnvironment('SUPABASE_PUBLISHABLE_KEY');
      final secretKey = _requiredEnvironment('BINGO_DEV_SECRET_KEY');
      final email = _requiredEnvironment('BINGO_MOBILE_TEST_EMAIL');
      final password = _requiredEnvironment('BINGO_MOBILE_TEST_PASSWORD');

      final client = SupabaseClient(url, publishableKey);
      final gateway = SupabaseAuthGateway(client);
      final adminClient = SupabaseClient(url, secretKey);
      SupabaseClient? unlinkedClient;
      String? temporaryUserId;
      SupabaseAuthGateway? restoredGateway;

      final existingUsers = await adminClient.auth.admin.listUsers(
        perPage: 1000,
      );
      for (final user in existingUsers) {
        if (user.email?.startsWith('bingo-unlinked-smoke-') ?? false) {
          await adminClient.auth.admin.deleteUser(user.id);
        }
      }

      addTearDown(() async {
        await unlinkedClient?.dispose();
        if (temporaryUserId != null) {
          await adminClient.auth.admin.deleteUser(temporaryUserId);
        }
        await adminClient.dispose();
        await restoredGateway?.close();
        await gateway.close();
      });

      await gateway.signIn(email: email, password: password);
      expect(await gateway.restoreSession(), isTrue);

      final userId = client.auth.currentUser?.id;
      expect(userId, isNotNull);
      expect(client.auth.currentSession, isNotNull);

      final profile = await gateway.profileRepository.loadProfile();
      expect(profile.id, isNotEmpty);
      expect(profile.name, isNotEmpty);
      expect(profile.classId, isNotEmpty);
      expect(profile.className, isNotEmpty);
      expect(profile.schoolId, isNotEmpty);
      expect(profile.schoolName, isNotEmpty);
      expect(profile.binCoinsBalance, greaterThanOrEqualTo(0));
      expect(profile.classXpBalance, greaterThanOrEqualTo(0));
      expect(profile.progress.studentId, profile.id);

      final journey = await gateway.journeyRepository.loadJourney();
      expect(journey, isNotNull);
      expect(journey!.stages, hasLength(3));
      expect(journey.campaignId, '61000000-0000-4000-8000-000000000001');

      final List<Map<String, dynamic>> journeyRows = List.from(
        await client.rpc('get_class_journey_v1'),
      );
      expect(journeyRows, hasLength(3));
      expect(journeyRows.map((row) => row['campaign_id']).toSet(), {
        journey.campaignId,
      });
      expect(journeyRows.first['total_units'], journey.totalUnits);
      expect(
        journeyRows.first['valid_deposit_count'],
        journey.validDepositCount,
      );
      expect(
        journeyRows.first['student_mission_completion_count'],
        journey.studentMissionCompletionCount,
      );
      expect(
        journeyRows.first['class_mission_completion_count'],
        journey.classMissionCompletionCount,
      );

      final List<Map<String, dynamic>> progressRows = List.from(
        await client.rpc('get_student_profile_progress_v1'),
      );
      expect(progressRows, hasLength(1));
      expect(progressRows.single['student_id'], profile.id);

      final List<Map<String, dynamic>> validDeposits = await client
          .from('deposits')
          .select('id')
          .eq('student_id', profile.id)
          .eq('is_valid', true);
      final expectedProgress = _expectedProgress(validDeposits.length);
      expect(profile.progress.validDepositCount, validDeposits.length);
      expect(profile.progress.levelNumber, expectedProgress.level);
      expect(profile.progress.levelCode, expectedProgress.code);
      expect(profile.progress.remainingToNextLevel, expectedProgress.remaining);
      expect(
        profile.progress.progressToNextLevel,
        closeTo(expectedProgress.progress, 0.000000001),
      );

      final List<Map<String, dynamic>> students = await client
          .from('students')
          .select(
            'id, auth_user_id, school_id, class_id, points_student_balance',
          )
          .eq('auth_user_id', userId!);
      expect(students, hasLength(1));
      expect(students.single['id'], profile.id);
      expect(students.single['school_id'], profile.schoolId);
      expect(students.single['class_id'], profile.classId);
      expect(
        students.single['points_student_balance'],
        profile.binCoinsBalance,
      );

      final List<Map<String, dynamic>> classes = await client
          .from('classes')
          .select('id, school_id, name, points_class_balance')
          .eq('id', profile.classId);
      expect(classes, hasLength(1));
      expect(classes.single['school_id'], profile.schoolId);
      expect(classes.single['name'], profile.className);
      expect(classes.single['points_class_balance'], profile.classXpBalance);

      final List<Map<String, dynamic>> schools = await client
          .from('schools')
          .select('id, name')
          .eq('id', profile.schoolId);
      expect(schools, hasLength(1));
      expect(schools.single['name'], profile.schoolName);

      final List<Map<String, dynamic>> otherStudents = await client
          .from('students')
          .select('id')
          .neq('id', profile.id)
          .limit(1);
      expect(otherStudents, isEmpty);

      final anonClient = SupabaseClient(url, publishableKey);
      var anonDenied = false;
      try {
        await anonClient.rpc('get_student_profile_progress_v1');
      } on PostgrestException {
        anonDenied = true;
      }
      expect(anonDenied, isTrue);

      var anonJourneyDenied = false;
      try {
        await anonClient.rpc('get_class_journey_v1');
      } on PostgrestException {
        anonJourneyDenied = true;
      } finally {
        await anonClient.dispose();
      }
      expect(anonJourneyDenied, isTrue);

      var secretRoleDenied = false;
      try {
        await adminClient.rpc('get_student_profile_progress_v1');
      } on PostgrestException {
        secretRoleDenied = true;
      }
      expect(secretRoleDenied, isTrue);

      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final temporaryEmail = 'bingo-unlinked-smoke-$uniqueSuffix@example.com';
      final temporaryPassword = 'B1ngo-Smoke-$uniqueSuffix!';
      final createdUser = await adminClient.auth.admin.createUser(
        AdminUserAttributes(
          email: temporaryEmail,
          password: temporaryPassword,
          emailConfirm: true,
        ),
      );
      temporaryUserId = createdUser.user?.id;
      expect(temporaryUserId, isNotNull);

      unlinkedClient = SupabaseClient(url, publishableKey);
      await unlinkedClient.auth.signInWithPassword(
        email: temporaryEmail,
        password: temporaryPassword,
      );
      final List<dynamic> unlinkedProgress = await unlinkedClient.rpc(
        'get_student_profile_progress_v1',
      );
      expect(unlinkedProgress, isEmpty);
      final List<dynamic> unlinkedJourney = await unlinkedClient.rpc(
        'get_class_journey_v1',
      );
      expect(unlinkedJourney, isEmpty);
      final List<Map<String, dynamic>> unlinkedStudents = await unlinkedClient
          .from('students')
          .select('id')
          .limit(1);
      expect(unlinkedStudents, isEmpty);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final customizationStore = SharedPreferencesCustomizationStore(
        preferences,
        studentId: profile.id,
      );
      const selectedCustomization = ProfileCustomization(
        avatarId: 'b1n-instruction',
        themeId: 'eco-green',
      );
      await customizationStore.saveCustomization(selectedCustomization);
      final reopenedStore = SharedPreferencesCustomizationStore(
        preferences,
        studentId: profile.id,
      );
      expect(await reopenedStore.loadCustomization(), selectedCustomization);
      final otherAccountStore = SharedPreferencesCustomizationStore(
        preferences,
        studentId: temporaryUserId,
      );
      expect(
        await otherAccountStore.loadCustomization(),
        const ProfileCustomization(),
      );

      final levelLabel = profile.progress.levelNumber == 0
          ? 'Nível 0'
          : 'Nível ${profile.progress.levelNumber} · '
                '${profile.progress.levelName}';
      expect(levelLabel, isNotEmpty);
      expect(_journeyMessage(profile.progress), isNotEmpty);

      final persistedSession = jsonEncode(client.auth.currentSession!);
      final restoredClient = SupabaseClient(url, publishableKey);
      final recovered = await restoredClient.auth.recoverSession(
        persistedSession,
      );
      expect(recovered.session, isNotNull);
      expect(restoredClient.auth.currentUser?.id, userId);

      restoredGateway = SupabaseAuthGateway(restoredClient);
      expect(await restoredGateway.restoreSession(), isTrue);
      final restoredProfile = await restoredGateway.profileRepository
          .loadProfile();
      expect(restoredProfile.id, profile.id);
      expect(restoredProfile.binCoinsBalance, profile.binCoinsBalance);
      expect(restoredProfile.classXpBalance, profile.classXpBalance);
      expect(
        restoredProfile.progress.validDepositCount,
        profile.progress.validDepositCount,
      );
      expect(await reopenedStore.loadCustomization(), selectedCustomization);

      await restoredGateway.signOut();
      expect(restoredClient.auth.currentSession, isNull);
      expect(restoredClient.auth.currentUser, isNull);

      stdout.writeln(
        'SMOKE_EVIDENCE '
        'login=true session=true student_rows=${students.length} '
        'class_rows=${classes.length} school_rows=${schools.length} '
        'bincoins=${profile.binCoinsBalance} '
        'class_xp=${profile.classXpBalance} '
        'valid_deposits=${profile.progress.validDepositCount} '
        'level=${profile.progress.levelNumber} '
        'level_code=${profile.progress.levelCode} '
        'remaining=${profile.progress.remainingToNextLevel} '
        'progress=${profile.progress.progressToNextLevel} '
        'other_student_rows=${otherStudents.length} '
        'unlinked_progress_rows=${unlinkedProgress.length} '
        'unlinked_journey_rows=${unlinkedJourney.length} '
        'anon_denied=$anonDenied '
        'anon_journey_denied=$anonJourneyDenied '
        'secret_role_denied=$secretRoleDenied '
        'journey_campaign=${journey.campaignId} '
        'journey_total=${journey.totalUnits} '
        'journey_valid_deposits=${journey.validDepositCount} '
        'journey_student_completions='
        '${journey.studentMissionCompletionCount} '
        'journey_class_completions=${journey.classMissionCompletionCount} '
        'customization_persisted=true customization_isolated=true '
        'profile_payload_valid=true '
        'restored=true logout=true',
      );
    },
    skip: !_hostedSmokeEnabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
