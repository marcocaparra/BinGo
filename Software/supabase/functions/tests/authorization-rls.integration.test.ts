import { deepStrictEqual, equal, ok } from "node:assert/strict";
import {
  createClient,
  type SupabaseClient,
  type User,
} from "@supabase/supabase-js";
import postgres from "postgres";

const integrationEnabled = Deno.env.get("BINGO_AUTH_RLS_INTEGRATION") === "1";

const PASSWORD = "Bingo-Rls-Test-2026!";

type TestDatabase = ReturnType<typeof postgres>;

type Fixture = Readonly<{
  schoolA: string;
  schoolB: string;
  classA: string;
  classB: string;
  classC: string;
  machineA: string;
  machineB: string;
  studentA: string;
  studentB: string;
  studentC: string;
  studentWithoutAuth: string;
  depositOwnOlder: string;
  depositOwnNewer: string;
  depositSameSchoolOther: string;
  depositOtherSchool: string;
  depositAnonymous: string;
  wasteCategory: string;
  authUserA: string;
}>;

type AuthenticatedFixture = Readonly<{
  userA: User;
  userB: User;
  userC: User;
  unlinkedUser: User;
}>;

Deno.test({
  name: "Supabase Auth and RLS isolate profile and personal deposit history",
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const supabaseUrl = requireEnvironment("SUPABASE_URL");
    const anonKey = requireEnvironment("SUPABASE_ANON_KEY");
    const serviceRoleKey = requireEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const machineId = requireEnvironment("BINGO_EDGE_TEST_MACHINE_ID");
    const database = postgres(
      requireEnvironment("BINGO_EDGE_TEST_DATABASE_URL"),
      { max: 1, prepare: false },
    );
    const admin = createClient(supabaseUrl, serviceRoleKey, clientOptions());
    const suffix = crypto.randomUUID();
    const createdUsers: User[] = [];
    let fixture: Fixture | null = null;

    try {
      const auth = await createAuthFixture(admin, suffix, createdUsers);
      fixture = await createDomainFixture(database, auth);

      const clientA = await authenticatedClient(
        supabaseUrl,
        anonKey,
        `rls-a-${suffix}@example.test`,
      );
      const clientB = await authenticatedClient(
        supabaseUrl,
        anonKey,
        `rls-b-${suffix}@example.test`,
      );
      const clientC = await authenticatedClient(
        supabaseUrl,
        anonKey,
        `rls-c-${suffix}@example.test`,
      );
      const unlinkedClient = await authenticatedClient(
        supabaseUrl,
        anonKey,
        `rls-unlinked-${suffix}@example.test`,
      );
      const anonClient = createClient(supabaseUrl, anonKey, clientOptions());

      await assertStudentIsolation(clientA, fixture);
      await assertDepositReadIsolation(clientA, fixture);
      await assertSchoolAndClassIsolation(
        clientA,
        clientB,
        clientC,
        fixture,
      );
      await assertUnlinkedIdentityHasNoDomainContext(
        unlinkedClient,
        fixture,
      );
      await assertAnonymousAccess(anonClient);
      await assertCriticalWritesAreDenied(clientA, database, fixture);
      await assertServiceRoleRemainsMinimal(admin, machineId);
      await assertDepositHistorySurvivesStudentTransfer(
        clientA,
        database,
        fixture,
      );
    } finally {
      if (fixture !== null) {
        await removeDomainFixture(database, fixture);
      }
      for (const user of createdUsers.reverse()) {
        await admin.auth.admin.deleteUser(user.id);
      }
      await database.end();
    }
  },
});

function clientOptions() {
  return {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  } as const;
}

async function createAuthFixture(
  admin: SupabaseClient,
  suffix: string,
  createdUsers: User[],
): Promise<AuthenticatedFixture> {
  async function create(label: string): Promise<User> {
    const { data, error } = await admin.auth.admin.createUser({
      email: `rls-${label}-${suffix}@example.test`,
      password: PASSWORD,
      email_confirm: true,
    });
    if (error || data.user === null) {
      throw new Error(`Unable to create Auth user ${label}: ${error?.message}`);
    }
    createdUsers.push(data.user);
    return data.user;
  }

  return {
    userA: await create("a"),
    userB: await create("b"),
    userC: await create("c"),
    unlinkedUser: await create("unlinked"),
  };
}

async function authenticatedClient(
  supabaseUrl: string,
  anonKey: string,
  email: string,
): Promise<SupabaseClient> {
  const client = createClient(supabaseUrl, anonKey, clientOptions());
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password: PASSWORD,
  });
  if (error || data.session === null || data.user === null) {
    throw new Error(`Unable to obtain a real Auth session for ${email}.`);
  }
  return client;
}

async function createDomainFixture(
  database: TestDatabase,
  auth: AuthenticatedFixture,
): Promise<Fixture> {
  const [category] = await database`
    select id
    from public.waste_categories
    where code = 'BATTERY'
  `;
  if (category === undefined) {
    throw new Error("Unable to find the BATTERY waste category fixture.");
  }

  const fixture: Fixture = {
    schoolA: crypto.randomUUID(),
    schoolB: crypto.randomUUID(),
    classA: crypto.randomUUID(),
    classB: crypto.randomUUID(),
    classC: crypto.randomUUID(),
    machineA: crypto.randomUUID(),
    machineB: crypto.randomUUID(),
    studentA: crypto.randomUUID(),
    studentB: crypto.randomUUID(),
    studentC: crypto.randomUUID(),
    studentWithoutAuth: crypto.randomUUID(),
    depositOwnOlder: crypto.randomUUID(),
    depositOwnNewer: crypto.randomUUID(),
    depositSameSchoolOther: crypto.randomUUID(),
    depositOtherSchool: crypto.randomUUID(),
    depositAnonymous: crypto.randomUUID(),
    wasteCategory: category.id,
    authUserA: auth.userA.id,
  };

  await database.begin(async (sql) => {
    await sql`
      insert into public.schools (id, name)
      values
        (${fixture.schoolA}::uuid, 'Escola RLS A'),
        (${fixture.schoolB}::uuid, 'Escola RLS B')
    `;
    await sql`
      insert into public.school_settings (school_id)
      values (${fixture.schoolA}::uuid), (${fixture.schoolB}::uuid)
    `;
    await sql`
      insert into public.classes (id, school_id, segment, grade, name, points_class_balance)
      values
        (${fixture.classA}::uuid, ${fixture.schoolA}::uuid, 'TEST', '1', 'Turma RLS A', 101),
        (${fixture.classB}::uuid, ${fixture.schoolA}::uuid, 'TEST', '2', 'Turma RLS B', 202),
        (${fixture.classC}::uuid, ${fixture.schoolB}::uuid, 'TEST', '3', 'Turma RLS C', 303)
    `;
    await sql`
      insert into public.machines (id, school_id, name, status)
      values
        (${fixture.machineA}::uuid, ${fixture.schoolA}::uuid, 'Maquina RLS A', 'ONLINE'),
        (${fixture.machineB}::uuid, ${fixture.schoolB}::uuid, 'Maquina RLS B', 'ONLINE')
    `;
    await sql`
      insert into public.students (
        id, school_id, class_id, name, points_student_balance, status, auth_user_id
      )
      values
        (${fixture.studentA}::uuid, ${fixture.schoolA}::uuid, ${fixture.classA}::uuid, 'Aluno RLS A', 11, 'ACTIVE', ${auth.userA.id}::uuid),
        (${fixture.studentB}::uuid, ${fixture.schoolA}::uuid, ${fixture.classB}::uuid, 'Aluno RLS B', 22, 'ACTIVE', ${auth.userB.id}::uuid),
        (${fixture.studentC}::uuid, ${fixture.schoolB}::uuid, ${fixture.classC}::uuid, 'Aluno RLS C', 33, 'ACTIVE', ${auth.userC.id}::uuid),
        (${fixture.studentWithoutAuth}::uuid, ${fixture.schoolA}::uuid, ${fixture.classA}::uuid, 'Aluno sem Auth', 44, 'ACTIVE', null)
    `;
    await sql`
      insert into public.deposits (
        id,
        event_id,
        school_id,
        machine_id,
        class_id,
        student_id,
        is_valid,
        detected_type,
        points_awarded_student,
        points_awarded_class,
        created_at,
        waste_category_id,
        category_source,
        bonus_rate_applied,
        bonus_bincoins_awarded
      )
      values
        (
          ${fixture.depositOwnOlder}::uuid, gen_random_uuid(), ${fixture.schoolA}::uuid,
          ${fixture.machineA}::uuid, ${fixture.classA}::uuid, ${fixture.studentA}::uuid,
          true, 'battery-own-older', 16, 19, '2026-01-01T10:00:00Z'::timestamptz,
          ${fixture.wasteCategory}::uuid, 'AI_CONFIRMED', 1, 8
        ),
        (
          ${fixture.depositOwnNewer}::uuid, gen_random_uuid(), ${fixture.schoolA}::uuid,
          ${fixture.machineA}::uuid, ${fixture.classA}::uuid, ${fixture.studentA}::uuid,
          true, 'battery-own-newer', 16, 19, '2026-01-02T10:00:00Z'::timestamptz,
          ${fixture.wasteCategory}::uuid, 'USER_CORRECTED', 1, 8
        ),
        (
          ${fixture.depositSameSchoolOther}::uuid, gen_random_uuid(), ${fixture.schoolA}::uuid,
          ${fixture.machineA}::uuid, ${fixture.classB}::uuid, ${fixture.studentB}::uuid,
          true, 'battery-same-school-other', 16, 19, '2026-01-03T10:00:00Z'::timestamptz,
          ${fixture.wasteCategory}::uuid, 'AI_CONFIRMED', 1, 8
        ),
        (
          ${fixture.depositOtherSchool}::uuid, gen_random_uuid(), ${fixture.schoolB}::uuid,
          ${fixture.machineB}::uuid, ${fixture.classC}::uuid, ${fixture.studentC}::uuid,
          true, 'battery-other-school', 16, 19, '2026-01-04T10:00:00Z'::timestamptz,
          ${fixture.wasteCategory}::uuid, 'AI_CONFIRMED', 1, 8
        ),
        (
          ${fixture.depositAnonymous}::uuid, gen_random_uuid(), ${fixture.schoolA}::uuid,
          ${fixture.machineA}::uuid, ${fixture.classA}::uuid, null,
          true, 'battery-anonymous', 0, 19, '2026-01-05T10:00:00Z'::timestamptz,
          ${fixture.wasteCategory}::uuid, 'AI_CONFIRMED', 0, 0
        )
    `;
  });

  return fixture;
}

async function assertDepositReadIsolation(
  clientA: SupabaseClient,
  fixture: Fixture,
): Promise<void> {
  const { data: ownDeposits, error: ownDepositsError } = await clientA
    .from("deposits")
    .select(
      "id, student_id, created_at, is_valid, detected_type, waste_category_id, category_source, bonus_bincoins_awarded, points_awarded_student, points_awarded_class",
    )
    .eq("student_id", fixture.studentA)
    .order("created_at", { ascending: false });
  assertNoError(ownDepositsError, "student A reads own deposit history");
  deepStrictEqual(
    ownDeposits?.map((deposit) => deposit.id),
    [fixture.depositOwnNewer, fixture.depositOwnOlder],
  );

  for (
    const [depositId, context] of [
      [fixture.depositSameSchoolOther, "another student from the same school"],
      [fixture.depositOtherSchool, "a student from another school"],
      [fixture.depositAnonymous, "an anonymous deposit"],
    ] as const
  ) {
    const { data, error } = await clientA
      .from("deposits")
      .select("id")
      .eq("id", depositId);
    assertNoError(error, `student A probes ${context}`);
    deepStrictEqual(data, []);
  }

  const { data: category, error: categoryError } = await clientA
    .from("waste_categories")
    .select("id, code, display_name")
    .eq("id", ownDeposits?.[0].waste_category_id ?? "")
    .single();
  assertNoError(categoryError, "student A reads the related waste category");
  equal(category?.id, fixture.wasteCategory);
  equal(category?.code, "BATTERY");

  const { error: internalColumnsError } = await clientA
    .from("deposits")
    .select("event_id, machine_id, school_id, class_id, bonus_rate_applied");
  assertDenied(
    internalColumnsError,
    "deposit history does not expose internal columns",
  );
}

async function assertStudentIsolation(
  clientA: SupabaseClient,
  fixture: Fixture,
): Promise<void> {
  const { data: ownRows, error: ownError } = await clientA
    .from("students")
    .select("id, name, school_id, class_id, points_student_balance, status");
  assertNoError(ownError, "student A reads own profile");
  deepStrictEqual(ownRows?.map((row) => row.id), [fixture.studentA]);

  const { data: studentBRows, error: studentBError } = await clientA
    .from("students")
    .select("id, name")
    .eq("id", fixture.studentB);
  assertNoError(studentBError, "student A probes student B");
  deepStrictEqual(studentBRows, []);

  const { data: studentWithoutAuthRows, error: studentWithoutAuthError } =
    await clientA
      .from("students")
      .select("id, name")
      .eq("id", fixture.studentWithoutAuth);
  assertNoError(
    studentWithoutAuthError,
    "student A probes a domain student without Auth",
  );
  deepStrictEqual(studentWithoutAuthRows, []);

  const { data: authUserRows, error: authUserIdError } = await clientA
    .from("students")
    .select("auth_user_id");
  assertNoError(
    authUserIdError,
    "auth_user_id is available because related policies require it",
  );
  deepStrictEqual(authUserRows, [{ auth_user_id: fixture.authUserA }]);

  const { error: pinHashError } = await clientA
    .from("students")
    .select("pin_hash");
  assertDenied(pinHashError, "pin_hash remains unavailable");
}

async function assertSchoolAndClassIsolation(
  clientA: SupabaseClient,
  clientB: SupabaseClient,
  clientC: SupabaseClient,
  fixture: Fixture,
): Promise<void> {
  const [schoolsA, schoolsB, schoolsC] = await Promise.all([
    readIds(clientA, "schools", "id, name"),
    readIds(clientB, "schools", "id, name"),
    readIds(clientC, "schools", "id, name"),
  ]);
  deepStrictEqual(schoolsA, [fixture.schoolA]);
  deepStrictEqual(schoolsB, [fixture.schoolA]);
  deepStrictEqual(schoolsC, [fixture.schoolB]);

  const [classesA, classesB, classesC] = await Promise.all([
    readIds(
      clientA,
      "classes",
      "id, school_id, segment, grade, name, points_class_balance",
    ),
    readIds(
      clientB,
      "classes",
      "id, school_id, segment, grade, name, points_class_balance",
    ),
    readIds(
      clientC,
      "classes",
      "id, school_id, segment, grade, name, points_class_balance",
    ),
  ]);
  deepStrictEqual(classesA, [fixture.classA]);
  deepStrictEqual(classesB, [fixture.classB]);
  deepStrictEqual(classesC, [fixture.classC]);
}

async function assertUnlinkedIdentityHasNoDomainContext(
  unlinkedClient: SupabaseClient,
  fixture: Fixture,
): Promise<void> {
  const [students, schools, classes, deposits] = await Promise.all([
    readIds(unlinkedClient, "students", "id, name"),
    readIds(unlinkedClient, "schools", "id, name"),
    readIds(unlinkedClient, "classes", "id, name"),
    readIds(unlinkedClient, "deposits", "id, student_id"),
  ]);
  ok(!students.includes(fixture.studentWithoutAuth));
  equal(students.length, 0);
  equal(schools.length, 0);
  equal(classes.length, 0);
  equal(deposits.length, 0);
}

async function assertAnonymousAccess(anonClient: SupabaseClient) {
  const { error: studentsError } = await anonClient
    .from("students")
    .select("id, name");
  assertDenied(studentsError, "anon cannot read students");

  const { error: depositsError } = await anonClient
    .from("deposits")
    .select("id");
  assertDenied(depositsError, "anon cannot read deposits");

  const { data: categories, error: categoriesError } = await anonClient
    .from("waste_categories")
    .select(
      "id, code, display_name, bonus_rate, is_active, created_at, updated_at",
    );
  assertNoError(categoriesError, "anon reads the complete global catalog");
  equal(categories?.length, 6);
}

async function assertCriticalWritesAreDenied(
  clientA: SupabaseClient,
  database: TestDatabase,
  fixture: Fixture,
): Promise<void> {
  const [studentBefore] = await database`
    select points_student_balance
    from public.students
    where id = ${fixture.studentA}::uuid
  `;
  const [classBefore] = await database`
    select points_class_balance
    from public.classes
    where id = ${fixture.classA}::uuid
  `;

  assertDenied(
    (await clientA.from("students").update({ points_student_balance: 999_999 })
      .eq("id", fixture.studentA)).error,
    "authenticated cannot update the student balance",
  );
  assertDenied(
    (await clientA.from("classes").update({ points_class_balance: 999_999 })
      .eq("id", fixture.classA)).error,
    "authenticated cannot update class XP",
  );
  assertDenied(
    (await clientA.from("deposits").insert({
      id: crypto.randomUUID(),
      event_id: crypto.randomUUID(),
      school_id: fixture.schoolA,
      machine_id: crypto.randomUUID(),
      class_id: fixture.classA,
      student_id: fixture.studentA,
      is_valid: false,
    })).error,
    "authenticated cannot insert a deposit",
  );
  assertDenied(
    (await clientA.from("deposits").update({ detected_type: "forged" })
      .eq("id", fixture.depositOwnOlder)).error,
    "authenticated cannot update a deposit",
  );
  assertDenied(
    (await clientA.from("deposits").delete()
      .eq("id", fixture.depositOwnOlder)).error,
    "authenticated cannot delete a deposit",
  );
  assertDenied(
    (await clientA.from("audit_logs").insert({
      school_id: fixture.schoolA,
      actor_type: "STUDENT",
      actor_id: fixture.studentA,
      action: "FORGED",
    })).error,
    "authenticated cannot write audit logs",
  );
  assertDenied(
    (await clientA.from("school_settings").update({
      deposit_bincoins_base: 999,
    }).eq("school_id", fixture.schoolA)).error,
    "authenticated cannot update school settings",
  );

  const [studentAfter] = await database`
    select points_student_balance
    from public.students
    where id = ${fixture.studentA}::uuid
  `;
  const [classAfter] = await database`
    select points_class_balance
    from public.classes
    where id = ${fixture.classA}::uuid
  `;
  const [depositAfter] = await database`
    select detected_type
    from public.deposits
    where id = ${fixture.depositOwnOlder}::uuid
  `;
  equal(
    studentAfter.points_student_balance,
    studentBefore.points_student_balance,
  );
  equal(classAfter.points_class_balance, classBefore.points_class_balance);
  equal(depositAfter.detected_type, "battery-own-older");
}

async function assertDepositHistorySurvivesStudentTransfer(
  clientA: SupabaseClient,
  database: TestDatabase,
  fixture: Fixture,
): Promise<void> {
  await database`
    update public.students
    set school_id = ${fixture.schoolB}::uuid,
        class_id = ${fixture.classC}::uuid,
        updated_at = now()
    where id = ${fixture.studentA}::uuid
  `;

  const [movedStudent] = await database`
    select school_id, class_id
    from public.students
    where id = ${fixture.studentA}::uuid
  `;
  equal(movedStudent.school_id, fixture.schoolB);
  equal(movedStudent.class_id, fixture.classC);

  const { data: historicalDeposits, error } = await clientA
    .from("deposits")
    .select("id, student_id, created_at")
    .eq("student_id", fixture.studentA)
    .order("created_at", { ascending: false });
  assertNoError(error, "student A reads history after changing schools");
  deepStrictEqual(
    historicalDeposits?.map((deposit) => deposit.id),
    [fixture.depositOwnNewer, fixture.depositOwnOlder],
  );
}

async function assertServiceRoleRemainsMinimal(
  admin: SupabaseClient,
  machineId: string,
): Promise<void> {
  const { data: machine, error: machineError } = await admin
    .from("machines")
    .select("id, school_id, api_key_hash")
    .eq("id", machineId)
    .single();
  assertNoError(machineError, "service_role reads machine credentials");
  equal(machine?.id, machineId);

  const { error: machineNameError } = await admin
    .from("machines")
    .select("name")
    .eq("id", machineId);
  assertDenied(machineNameError, "service_role cannot read machines.name");

  const { error: machineWriteError } = await admin
    .from("machines")
    .update({ last_seen: new Date().toISOString() })
    .eq("id", machineId);
  assertDenied(machineWriteError, "service_role cannot write machines");
}

async function readIds(
  client: SupabaseClient,
  table: string,
  columns: string,
): Promise<string[]> {
  const { data, error } = await client.from(table).select(columns).order("id");
  assertNoError(error, `read ${table}`);
  const rows = (data ?? []) as unknown as Array<{ id: string }>;
  return rows.map((row) => row.id);
}

async function removeDomainFixture(
  database: TestDatabase,
  fixture: Fixture,
): Promise<void> {
  await database.begin(async (sql) => {
    for (
      const depositId of [
        fixture.depositOwnOlder,
        fixture.depositOwnNewer,
        fixture.depositSameSchoolOther,
        fixture.depositOtherSchool,
        fixture.depositAnonymous,
      ]
    ) {
      await sql`delete from public.deposits where id = ${depositId}::uuid`;
    }
    for (
      const studentId of [
        fixture.studentA,
        fixture.studentB,
        fixture.studentC,
        fixture.studentWithoutAuth,
      ]
    ) {
      await sql`delete from public.students where id = ${studentId}::uuid`;
    }
    for (const machineId of [fixture.machineA, fixture.machineB]) {
      await sql`delete from public.machines where id = ${machineId}::uuid`;
    }
    for (const classId of [fixture.classA, fixture.classB, fixture.classC]) {
      await sql`delete from public.classes where id = ${classId}::uuid`;
    }
    for (const schoolId of [fixture.schoolA, fixture.schoolB]) {
      await sql`delete from public.school_settings where school_id = ${schoolId}::uuid`;
      await sql`delete from public.schools where id = ${schoolId}::uuid`;
    }
  });
}

function assertNoError(
  error: { code?: string; message?: string } | null,
  context: string,
): void {
  if (error !== null) {
    throw new Error(`${context}: ${error.code} ${error.message}`);
  }
}

function assertDenied(
  error: { code?: string; message?: string } | null,
  context: string,
): void {
  if (error === null) {
    throw new Error(`${context}: operation unexpectedly succeeded`);
  }
  equal(error.code, "42501", `${context}: unexpected SQLSTATE`);
}

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing integration test environment: ${name}`);
  }
  return value;
}
