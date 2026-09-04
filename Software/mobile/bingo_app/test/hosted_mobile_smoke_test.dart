import 'dart:convert';
import 'dart:io';

import 'package:bingo_app/src/auth/supabase_auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _hostedSmokeEnabled = Platform.environment['BINGO_HOSTED_SMOKE'] == '1';

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Variável obrigatória ausente: $name');
  }
  return value;
}

void main() {
  test(
    'smoke hospedado Auth, perfil RLS, restauração e logout',
    () async {
      final url = _requiredEnvironment('SUPABASE_URL');
      final publishableKey = _requiredEnvironment('SUPABASE_PUBLISHABLE_KEY');
      final email = _requiredEnvironment('BINGO_MOBILE_TEST_EMAIL');
      final password = _requiredEnvironment('BINGO_MOBILE_TEST_PASSWORD');

      final client = SupabaseClient(url, publishableKey);
      final gateway = SupabaseAuthGateway(client);
      SupabaseAuthGateway? restoredGateway;

      addTearDown(() async {
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

      await restoredGateway.signOut();
      expect(restoredClient.auth.currentSession, isNull);
      expect(restoredClient.auth.currentUser, isNull);

      stdout.writeln(
        'SMOKE_EVIDENCE '
        'login=true session=true student_rows=${students.length} '
        'class_rows=${classes.length} school_rows=${schools.length} '
        'bincoins=${profile.binCoinsBalance} '
        'class_xp=${profile.classXpBalance} '
        'other_student_rows=${otherStudents.length} '
        'restored=true logout=true',
      );
    },
    skip: !_hostedSmokeEnabled,
  );
}
