import { deepStrictEqual, equal, match } from "node:assert/strict";

import type { MachineLookup } from "../_shared/machine-auth.ts";
import { createHealthHandler } from "../health-v1/handler.ts";

const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const SCHOOL_ID = "10000000-0000-4000-8000-000000000001";
const API_KEY = "edge-demo-key";
const API_KEY_HASH =
  "YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI=";
const CHECKED_AT = "2026-08-15T12:00:00.000Z";

function machineRow() {
  return {
    id: MACHINE_ID,
    school_id: SCHOOL_ID,
    api_key_hash: API_KEY_HASH,
  };
}

function healthRequest(
  method = "GET",
  auth: "valid" | "missing" | "invalid" = "valid",
): Request {
  const headers = new Headers();
  if (auth !== "missing") {
    headers.set("X-Machine-Id", MACHINE_ID);
    headers.set("X-Api-Key", auth === "valid" ? API_KEY : "wrong-key");
  }
  return new Request("http://localhost/functions/v1/health-v1", {
    method,
    headers,
  });
}

function trustedLookup(): MachineLookup {
  return () => Promise.resolve(machineRow());
}

async function responseBody(response: Response): Promise<unknown> {
  return await response.json();
}

Deno.test("validates the GET method before technical authentication", async () => {
  let lookupCount = 0;
  let readinessCount = 0;
  const handler = createHealthHandler({
    machineAuth: {
      lookupMachine: () => {
        lookupCount += 1;
        return Promise.resolve(machineRow());
      },
    },
    checkReadiness: () => {
      readinessCount += 1;
      return Promise.resolve(true);
    },
  });

  const response = await handler(healthRequest("POST", "missing"));

  equal(response.status, 405);
  equal(response.headers.get("allow"), "GET");
  equal(response.headers.has("access-control-allow-origin"), false);
  equal(lookupCount, 0);
  equal(readinessCount, 0);
});

Deno.test("returns AVAILABLE only after authentication and a positive readiness check", async () => {
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () => Promise.resolve(true),
    now: () => new Date(CHECKED_AT),
  });

  const response = await handler(healthRequest());

  equal(response.status, 200);
  equal(response.headers.get("cache-control"), "no-store");
  deepStrictEqual(await responseBody(response), {
    status: "AVAILABLE",
    can_start_deposit: true,
    scope: "CENTRAL_BACKEND",
    checked_at: CHECKED_AT,
  });
});

Deno.test("returns 503 UNAVAILABLE only for a proven negative readiness result", async () => {
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () => Promise.resolve(false),
    now: () => new Date(CHECKED_AT),
  });

  const response = await handler(healthRequest());

  equal(response.status, 503);
  deepStrictEqual(await responseBody(response), {
    status: "UNAVAILABLE",
    can_start_deposit: false,
    scope: "CENTRAL_BACKEND",
    checked_at: CHECKED_AT,
  });
});

Deno.test("keeps invalid credentials as 401 and does not execute readiness", async () => {
  let readinessCount = 0;
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () => {
      readinessCount += 1;
      return Promise.resolve(true);
    },
  });

  for (const auth of ["missing", "invalid"] as const) {
    const response = await handler(healthRequest("GET", auth));
    equal(response.status, 401);
    equal(
      (await responseBody(response) as { error: { code: string } }).error.code,
      "MACHINE_AUTHENTICATION_FAILED",
    );
  }
  equal(readinessCount, 0);
});

Deno.test("keeps an authentication infrastructure failure outside the health state", async () => {
  let readinessCount = 0;
  const handler = createHealthHandler({
    machineAuth: {
      lookupMachine: () =>
        Promise.reject(new Error("sensitive Data API failure")),
    },
    checkReadiness: () => {
      readinessCount += 1;
      return Promise.resolve(true);
    },
  });

  const response = await handler(healthRequest());
  const body = JSON.stringify(await responseBody(response));

  equal(response.status, 500);
  equal(readinessCount, 0);
  match(body, /^((?!sensitive|Data API|service_role|api_key_hash).)*$/);
});

Deno.test("fails closed with 500 on readiness timeout without claiming 503", async () => {
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () =>
      Promise.reject(new DOMException("internal timeout", "TimeoutError")),
  });

  const response = await handler(healthRequest());
  const body = await responseBody(response) as {
    error: { code: string; message: string };
  };

  equal(response.status, 500);
  deepStrictEqual(body, {
    error: { code: "INTERNAL_ERROR", message: "Erro interno do servidor." },
  });
});

Deno.test("fails closed when the RPC does not return a boolean", async () => {
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () => Promise.resolve({ ready: true }),
  });

  const response = await handler(healthRequest());

  equal(response.status, 500);
  equal(
    (await responseBody(response) as { error: { code: string } }).error.code,
    "INTERNAL_ERROR",
  );
});

Deno.test("has no local state and reports recovery on a later request", async () => {
  const results = [false, true];
  const handler = createHealthHandler({
    machineAuth: { lookupMachine: trustedLookup() },
    checkReadiness: () => Promise.resolve(results.shift()),
    now: () => new Date(CHECKED_AT),
  });

  equal((await handler(healthRequest())).status, 503);
  const recovered = await handler(healthRequest());
  equal(recovered.status, 200);
  equal(
    (await responseBody(recovered) as { status: string }).status,
    "AVAILABLE",
  );
});
