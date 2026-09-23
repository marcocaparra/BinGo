import { deepStrictEqual, equal } from "node:assert/strict";
import postgres from "postgres";

import { createHealthHandler } from "../health-v1/handler.ts";

const integrationEnabled =
  Deno.env.get("BINGO_EDGE_HEALTH_INTEGRATION") === "1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const API_KEY = "edge-demo-key";

type TestDatabase = ReturnType<typeof postgres>;

function healthHeaders(apiKey = API_KEY): Headers {
  return new Headers({
    "X-Machine-Id": MACHINE_ID,
    "X-Api-Key": apiKey,
  });
}

async function callHealth(
  method = "GET",
  headers: Headers = healthHeaders(),
): Promise<Response> {
  return await createHealthHandler()(
    new Request(
      "http://localhost/functions/v1/health-v1",
      {
        method,
        headers,
      },
    ),
  );
}

async function writeSnapshot(database: TestDatabase) {
  const [row] = await database`
    select
      (select count(*)::integer from public.deposits) as deposits,
      (select count(*)::integer from public.audit_logs) as audits,
      (select coalesce(sum(points_student_balance), 0)::bigint from public.students) as student_balance,
      (select coalesce(sum(points_class_balance), 0)::bigint from public.classes) as class_balance
  `;
  return row;
}

Deno.test({
  name: "health-v1 authenticates, proves readiness and has no database effects",
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const database = postgres(
      requireEnvironment("BINGO_EDGE_TEST_DATABASE_URL"),
      { max: 1, prepare: false },
    );
    try {
      const before = await writeSnapshot(database);

      for (let attempt = 0; attempt < 2; attempt += 1) {
        const response = await callHealth();
        equal(response.status, 200);
        equal(response.headers.get("cache-control"), "no-store");
        const body = await response.json() as Record<string, unknown>;
        equal(body.status, "AVAILABLE");
        equal(body.can_start_deposit, true);
        equal(body.scope, "CENTRAL_BACKEND");
        equal(typeof body.checked_at, "string");
        equal(Number.isNaN(Date.parse(body.checked_at as string)), false);
      }

      const missing = await callHealth("GET", new Headers());
      equal(missing.status, 401);
      equal(
        (await missing.json() as { error: { code: string } }).error.code,
        "MACHINE_AUTHENTICATION_FAILED",
      );

      const invalid = await callHealth("GET", healthHeaders("wrong-key"));
      equal(invalid.status, 401);

      const malformedHeaders = healthHeaders();
      malformedHeaders.set("X-Machine-Id", "not-a-uuid");
      equal((await callHealth("GET", malformedHeaders)).status, 401);

      const unsupported = await callHealth("POST", new Headers());
      equal(unsupported.status, 405);
      equal(unsupported.headers.get("allow"), "GET");

      deepStrictEqual(await writeSnapshot(database), before);
    } finally {
      await database.end();
    }
  },
});

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing integration test environment: ${name}`);
  }
  return value;
}
