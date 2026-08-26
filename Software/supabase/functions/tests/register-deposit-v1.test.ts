import { deepStrictEqual, equal, match } from "node:assert/strict";

import {
  createRegisterDepositHandler,
  type RegisterDeposit,
  type RegisterDepositRpcRow,
} from "../register-deposit-v1/handler.ts";

const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const SCHOOL_ID = "10000000-0000-4000-8000-000000000001";
const CLASS_ID = "20000000-0000-4000-8000-000000000001";
const STUDENT_ID = "30000000-0000-4000-8000-000000000001";
const EVENT_ID = "50000000-0000-4000-8000-000000000001";
const DEMO_API_KEY = "edge-demo-key";
const DEMO_API_KEY_HASH =
  "YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI=";

const CREATED_ROW: RegisterDepositRpcRow = {
  deposit_id: "60000000-0000-4000-8000-000000000001",
  event_id: EVENT_ID,
  waste_category_code: "BATTERY",
  category_source: "AI_CONFIRMED",
  bonus_rate_applied: "1.0000",
  bonus_bincoins_awarded: 8,
  points_awarded_student: 16,
  points_awarded_class: 19,
  created_at: "2026-08-13T00:00:00.000Z",
  was_replayed: false,
};

function validBody(overrides: Record<string, unknown> = {}) {
  return {
    event_id: EVENT_ID,
    class_id: CLASS_ID,
    student_id: STUDENT_ID,
    is_valid: true,
    detected_type: "battery",
    waste_category_code: "BATTERY",
    category_source: "AI_CONFIRMED",
    ...overrides,
  };
}

function machineRow() {
  return {
    id: MACHINE_ID,
    school_id: SCHOOL_ID,
    api_key_hash: DEMO_API_KEY_HASH,
  };
}

function request(
  body: unknown = validBody(),
  options: {
    method?: string;
    machineId?: string | null;
    apiKey?: string | null;
    rawBody?: string;
    contentType?: string | null;
  } = {},
): Request {
  const headers = new Headers();
  if (options.machineId !== null) {
    headers.set("X-Machine-Id", options.machineId ?? MACHINE_ID);
  }
  if (options.apiKey !== null) {
    headers.set("X-Api-Key", options.apiKey ?? DEMO_API_KEY);
  }
  if (options.contentType !== null) {
    headers.set("Content-Type", options.contentType ?? "application/json");
  }

  const method = options.method ?? "POST";
  return new Request("http://localhost/functions/v1/register-deposit-v1", {
    method,
    headers,
    body: method === "GET"
      ? undefined
      : options.rawBody ?? JSON.stringify(body),
  });
}

function handler(registerDeposit: RegisterDeposit, onLookup?: () => void) {
  return createRegisterDepositHandler({
    machineAuth: {
      lookupMachine: () => {
        onLookup?.();
        return Promise.resolve(machineRow());
      },
    },
    registerDeposit,
  });
}

async function json(response: Response): Promise<unknown> {
  return await response.json();
}

function successfulRegister(row = CREATED_ROW): RegisterDeposit {
  return () => Promise.resolve({ row, error: null });
}

Deno.test("rejects unsupported methods before machine authentication", async () => {
  let lookupCount = 0;
  let rpcCount = 0;
  const response = await handler(
    () => {
      rpcCount += 1;
      return Promise.resolve({ row: CREATED_ROW, error: null });
    },
    () => lookupCount += 1,
  )(request(undefined, { method: "GET", machineId: null, apiKey: null }));

  equal(response.status, 405);
  equal(response.headers.get("allow"), "POST");
  equal(response.headers.get("access-control-allow-origin"), null);
  equal(lookupCount, 0);
  equal(rpcCount, 0);
});

Deno.test("returns persisted RPC snapshot for an identified valid deposit", async () => {
  let received: unknown;
  const response = await handler((body, machine) => {
    received = { body, machine };
    return Promise.resolve({ row: CREATED_ROW, error: null });
  })(request());

  equal(response.status, 201);
  deepStrictEqual(received, {
    body: validBody(),
    machine: { id: MACHINE_ID, schoolId: SCHOOL_ID },
  });
  deepStrictEqual(await json(response), {
    id: CREATED_ROW.deposit_id,
    event_id: CREATED_ROW.event_id,
    waste_category_code: "BATTERY",
    category_source: "AI_CONFIRMED",
    bonus_rate_applied: "1.0000",
    bonus_bincoins_awarded: 8,
    points_awarded_student: 16,
    points_awarded_class: 19,
    created_at: CREATED_ROW.created_at,
  });
});

Deno.test("accepts anonymous valid and invalid deposits with documented combinations", async () => {
  const receivedBodies: unknown[] = [];
  const register: RegisterDeposit = (body) => {
    receivedBodies.push(body);
    return Promise.resolve({
      row: {
        ...CREATED_ROW,
        waste_category_code: body.waste_category_code,
        category_source: body.category_source,
        points_awarded_student: 0,
        points_awarded_class: body.is_valid ? 19 : 0,
      },
      error: null,
    });
  };
  const run = handler(register);

  const anonymous = await run(request(validBody({ student_id: null })));
  const invalid = await run(request(validBody({
    event_id: "50000000-0000-4000-8000-000000000002",
    student_id: null,
    is_valid: false,
    waste_category_code: null,
    category_source: null,
  })));

  equal(anonymous.status, 201);
  equal(invalid.status, 201);
  equal(receivedBodies.length, 2);
  deepStrictEqual(
    (receivedBodies[1] as Record<string, unknown>).category_source,
    null,
  );

  const invalidWithOmissions = await run(request({
    event_id: "50000000-0000-4000-8000-000000000003",
    class_id: CLASS_ID,
    is_valid: false,
  }));
  equal(invalidWithOmissions.status, 201);
  deepStrictEqual(receivedBodies[2], {
    event_id: "50000000-0000-4000-8000-000000000003",
    class_id: CLASS_ID,
    student_id: null,
    is_valid: false,
    detected_type: null,
    waste_category_code: null,
    category_source: null,
  });
});

Deno.test("returns uniform 401 for absent or incorrect technical credentials", async () => {
  const run = handler(successfulRegister());
  for (
    const candidate of [
      request(validBody(), { machineId: null }),
      request(validBody(), { apiKey: null }),
      request(validBody(), { apiKey: "wrong-key" }),
    ]
  ) {
    const response = await run(candidate);
    equal(response.status, 401);
    deepStrictEqual(await json(response), {
      error: {
        code: "MACHINE_AUTHENTICATION_FAILED",
        message: "Credenciais técnicas inválidas.",
      },
    });
  }
});

Deno.test("rejects malformed JSON, non-JSON content and non-object bodies", async () => {
  let rpcCount = 0;
  const run = handler(() => {
    rpcCount += 1;
    return Promise.resolve({ row: CREATED_ROW, error: null });
  });
  const candidates = [
    request(undefined, { rawBody: "{" }),
    request(validBody(), { contentType: "text/plain" }),
    request([]),
    request(null),
  ];

  for (const candidate of candidates) {
    const response = await run(candidate);
    equal(response.status, 422);
    equal(
      (await json(response) as { error: { code: string } }).error.code,
      "INVALID_DEPOSIT_CONTRACT",
    );
  }
  equal(rpcCount, 0);
});

Deno.test("rejects every extra field, including authority and reward claims", async () => {
  let rpcCount = 0;
  const run = handler(() => {
    rpcCount += 1;
    return Promise.resolve({ row: CREATED_ROW, error: null });
  });

  for (
    const field of [
      "machine_id",
      "school_id",
      "size",
      "quantity",
      "bincoins",
      "xp",
      "bonus_rate",
      "bonus_bincoins_awarded",
      "points_awarded_student",
      "points_awarded_class",
    ]
  ) {
    const response = await run(request(validBody({ [field]: 999 })));
    equal(response.status, 422, field);
  }
  equal(rpcCount, 0);
});

Deno.test("rejects malformed event, class and student UUIDs", async () => {
  const run = handler(successfulRegister());
  for (
    const body of [
      validBody({ event_id: "invalid" }),
      validBody({ class_id: "invalid" }),
      validBody({ student_id: "invalid" }),
    ]
  ) {
    equal((await run(request(body))).status, 422);
  }
});

Deno.test("rejects invalid category and origin combinations", async () => {
  const run = handler(successfulRegister());
  for (
    const body of [
      validBody({ waste_category_code: "NOT_CANONICAL" }),
      validBody({ category_source: "NOT_A_SOURCE" }),
      validBody({
        waste_category_code: "UNKNOWN",
        category_source: "AI_CONFIRMED",
      }),
      validBody({
        waste_category_code: "BATTERY",
        category_source: "UNIDENTIFIED",
      }),
      validBody({ waste_category_code: null }),
      validBody({ category_source: null }),
      validBody({ is_valid: false }),
    ]
  ) {
    equal((await run(request(body))).status, 422);
  }
});

Deno.test("maps only the SQLSTATEs proven by the RPC tests", async () => {
  const cases = [
    [{ code: "23505", message: "raw conflict" }, 409, "EVENT_ID_CONFLICT"],
    [
      { code: "23503", message: "raw relation" },
      404,
      "DEPOSIT_CONTEXT_NOT_FOUND",
    ],
    [{ code: "23514", message: "raw check" }, 422, "INVALID_DEPOSIT_CONTRACT"],
    [
      {
        code: "P0002",
        message: "Categoria de lixo eletronico inexistente ou inativa.",
      },
      404,
      "WASTE_CATEGORY_NOT_FOUND",
    ],
    [
      { code: "P0002", message: "Maquina nao encontrada." },
      500,
      "INTERNAL_ERROR",
    ],
  ] as const;

  for (const [error, status, code] of cases) {
    const response = await handler(() => Promise.resolve({ row: null, error }))(
      request(),
    );
    const serialized = JSON.stringify(await json(response));
    equal(response.status, status);
    equal(
      (JSON.parse(serialized) as { error: { code: string } }).error.code,
      code,
    );
    match(serialized, /^((?!raw|SQL|PostgREST|service_role).)*$/);
  }
});

Deno.test("uses 200 for an identical replay and omits internal replay metadata", async () => {
  const response = await handler(successfulRegister({
    ...CREATED_ROW,
    was_replayed: true,
  }))(request());
  const body = await json(response) as Record<string, unknown>;

  equal(response.status, 200);
  equal("was_replayed" in body, false);
});

Deno.test("contains unexpected RPC failures behind the public 500 envelope", async () => {
  const response = await handler(() =>
    Promise.reject(new Error("secret SQL and service_role details"))
  )(request());
  const serialized = JSON.stringify(await json(response));

  equal(response.status, 500);
  deepStrictEqual(JSON.parse(serialized), {
    error: { code: "INTERNAL_ERROR", message: "Erro interno do servidor." },
  });
  match(serialized, /^((?!secret|SQL|service_role).)*$/);
});
