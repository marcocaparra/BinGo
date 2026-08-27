class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.name,
    required this.schoolId,
    required this.schoolName,
    required this.classId,
    required this.className,
    required this.pointsStudentBalance,
    required this.pointsClassBalance,
    required this.status,
  });

  final String id;
  final String name;
  final String schoolId;
  final String schoolName;
  final String classId;
  final String className;
  final int pointsStudentBalance;
  final int pointsClassBalance;
  final String status;

  int get binCoinsBalance => pointsStudentBalance;

  int get classXpBalance => pointsClassBalance;
}

enum ProfileFailureKind {
  network,
  sessionInvalid,
  authLinkMissing,
  notFound,
  malformedData,
  unknown,
}

class ProfileFailure implements Exception {
  const ProfileFailure(this.kind, this.message, [this.cause]);

  final ProfileFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class ProfileRepository {
  Future<StudentProfile> loadProfile();
}
