import { deepStrictEqual, equal } from "node:assert/strict";
import postgres from "postgres";

const integrationEnabled =
  Deno.env.get("BINGO_EDGE_DEPOSIT_INTEGRATION") === "1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const CLASS_ID = "20000000-0000-4000-8000-000000000001";
const STUDENT_ID = "30000000-0000-4000-8000-000000000001";
const STUDENT_FROM_ANOTHER_CLASS = "30000000-0000-4000-8000-000000000011";
const API_KEY = "edge-demo-key";

type DepositResponse = Readonly<{
  id: string;
  event_id: string;
  waste_category_code: string | null;
  category_source: string | null;
  bonus_rate_applied: string | number;
  bonus_bincoins_awarded: number;
  points_awarded_student: number;
  points_awarded_class: number;
  created_at: string;
}>;

type TestDatabase = ReturnType<typeof postgres>;

function validBody(eventId: string, overrides: Record<string, unknown> = {}) {
  return {
    event_id: eventId,
    class_id: CLASS_ID,
    student_id: STUDENT_ID,
    is_valid: true,
    detected_type: "battery",
    waste_category_code: "BATTERY",
    category_source: "AI_CONFIRMED",
    ...overrides,
  };
}

async function post(
  body: unknown,
  auth: "valid" | "missing" | "invalid" = "valid",
): Promise<Response> {
  const endpoint = requireEnvironment("BINGO_EDGE_DEPOSIT_URL");
  const headers = new Headers({ "Content-Type": "application/json" });
  if (auth !== "missing") {
    headers.set("X-Machine-Id", MACHINE_ID);
    headers.set("X-Api-Key", auth === "valid" ? API_KEY : "wrong-key");
  }
  return await fetch(endpoint, {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function balanceSnapshot(database: TestDatabase) {
  const [student] = await database`
    select points_student_balance
    from public.students
    where id = ${STUDENT_ID}::uuid
  `;
  const [classRow] = await database`
    select points_class_balance
    from public.classes
    where id = ${CLASS_ID}::uuid
  `;
  return {
    student: student.points_student_balance as number,
    class: classRow.points_class_balance as number,
  };
}

async function eventEffects(database: TestDatabase, eventId: string) {
  const [deposits] = await database`
    select count(*)::integer as count
    from public.deposits
    where event_id = ${eventId}::uuid
  `;
  const [audits] = await database`
    select count(*)::integer as count
    from public.audit_logs
    where metadata ->> 'event_id' = ${eventId}
  `;
  return { deposits: deposits.count, audits: audits.count };
}

async function expectError(
  response: Response,
  status: number,
  code: string,
): Promise<void> {
  equal(response.status, status);
  const body = await response.json() as { error: { code: string } };
  equal(body.error.code, code);
}

Deno.test({
  name: "register-deposit-v1 HTTP contract and database effects",
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const database = postgres(
      requireEnvironment("BINGO_EDGE_TEST_DATABASE_URL"),
      {
        max: 1,
        prepare: false,
      },
    );
    try {
      await exerciseDepositContract(database);
    } finally {
      await database.end();
    }
  },
});

async function exerciseDepositContract(database: TestDatabase): Promise<void> {
  const before = await balanceSnapshot(database);
  const eventId = crypto.randomUUID();
  const payload = validBody(eventId);

  const createdResponse = await post(payload);
  equal(createdResponse.status, 201);
  const created = await createdResponse.json() as DepositResponse;
  equal(created.event_id, eventId);
  equal(created.category_source, "AI_CONFIRMED");

  const afterCreation = await balanceSnapshot(database);
  deepStrictEqual(await eventEffects(database, eventId), {
    deposits: 1,
    audits: 1,
  });
  equal(
    afterCreation.student - before.student,
    created.points_awarded_student,
  );
  equal(afterCreation.class - before.class, created.points_awarded_class);

  const replayResponse = await post(payload);
  equal(replayResponse.status, 200);
  deepStrictEqual(await replayResponse.json(), created);
  deepStrictEqual(await eventEffects(database, eventId), {
    deposits: 1,
    audits: 1,
  });
  deepStrictEqual(await balanceSnapshot(database), afterCreation);

  await expectError(
    await post(validBody(eventId, {
      waste_category_code: "MOBILE_DEVICE",
      detected_type: "mobile",
    })),
    409,
    "EVENT_ID_CONFLICT",
  );
  deepStrictEqual(await eventEffects(database, eventId), {
    deposits: 1,
    audits: 1,
  });
  deepStrictEqual(await balanceSnapshot(database), afterCreation);

  const concurrentEventId = crypto.randomUUID();
  const concurrentBefore = await balanceSnapshot(database);
  const concurrentPayload = validBody(concurrentEventId);
  const concurrentResponses = await Promise.all([
    post(concurrentPayload),
    post(concurrentPayload),
  ]);
  deepStrictEqual(
    concurrentResponses.map((response) => response.status).sort(),
    [200, 201],
  );
  const concurrentBodies = await Promise.all(
    concurrentResponses.map((response) => response.json()),
  );
  deepStrictEqual(concurrentBodies[0], concurrentBodies[1]);
  const concurrentCreated = concurrentBodies[0] as DepositResponse;
  const concurrentAfter = await balanceSnapshot(database);
  deepStrictEqual(await eventEffects(database, concurrentEventId), {
    deposits: 1,
    audits: 1,
  });
  equal(
    concurrentAfter.student - concurrentBefore.student,
    concurrentCreated.points_awarded_student,
  );
  equal(
    concurrentAfter.class - concurrentBefore.class,
    concurrentCreated.points_awarded_class,
  );

  const anonymous = await post(validBody(crypto.randomUUID(), {
    student_id: null,
    waste_category_code: "PERIPHERAL",
    category_source: "USER_CORRECTED",
  }));
  equal(anonymous.status, 201);
  const anonymousBody = await anonymous.json() as DepositResponse;
  equal(anonymousBody.points_awarded_student, 0);
  equal(anonymousBody.points_awarded_class, 1900);

  const invalid = await post(validBody(crypto.randomUUID(), {
    student_id: null,
    is_valid: false,
    waste_category_code: null,
    category_source: null,
  }));
  equal(invalid.status, 201);
  const invalidBody = await invalid.json() as DepositResponse;
  equal(invalidBody.points_awarded_student, 0);
  equal(invalidBody.points_awarded_class, 0);

  await expectError(
    await post(payload, "missing"),
    401,
    "MACHINE_AUTHENTICATION_FAILED",
  );
  await expectError(
    await post(payload, "invalid"),
    401,
    "MACHINE_AUTHENTICATION_FAILED",
  );
  await expectError(await post("{"), 422, "INVALID_DEPOSIT_CONTRACT");
  await expectError(
    await post(
      validBody(crypto.randomUUID(), { points_awarded_student: 999 }),
    ),
    422,
    "INVALID_DEPOSIT_CONTRACT",
  );
  await expectError(
    await post(validBody("not-a-uuid")),
    422,
    "INVALID_DEPOSIT_CONTRACT",
  );
  await expectError(
    await post(validBody(crypto.randomUUID(), {
      category_source: "UNIDENTIFIED",
    })),
    422,
    "INVALID_DEPOSIT_CONTRACT",
  );
  await expectError(
    await post(validBody(crypto.randomUUID(), {
      student_id: STUDENT_FROM_ANOTHER_CLASS,
    })),
    404,
    "DEPOSIT_CONTEXT_NOT_FOUND",
  );
  await expectError(
    await post(validBody(crypto.randomUUID(), {
      class_id: crypto.randomUUID(),
    })),
    404,
    "DEPOSIT_CONTEXT_NOT_FOUND",
  );

  await database`
      update public.waste_categories
      set is_active = false
      where code = 'CABLE_WIRE'
    `;
  let categoryRestoreFailed = false;
  try {
    await expectError(
      await post(validBody(crypto.randomUUID(), {
        detected_type: "cable",
        waste_category_code: "CABLE_WIRE",
      })),
      404,
      "WASTE_CATEGORY_NOT_FOUND",
    );
  } finally {
    try {
      await database`
          update public.waste_categories
          set is_active = true
          where code = 'CABLE_WIRE'
        `;
    } catch {
      categoryRestoreFailed = true;
    }
  }
  if (categoryRestoreFailed) {
    throw new Error("Unable to restore category after integration test.");
  }
}

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing integration test environment: ${name}`);
  }
  return value;
}
