import { deepStrictEqual, equal, match } from "node:assert/strict";

import {
  createMissionRecoveryHandler,
  type MissionRecoveryRow,
  type RecoverNextMissionEvent,
} from "../recover-missions-v1/handler.ts";

const EVENT_A = "a0000000-0000-4000-8000-000000000001";
const EVENT_B = "a0000000-0000-4000-8000-000000000002";

function request(
  options: {
    method?: string;
    apiKey?: string;
    authorization?: string;
    body?: unknown;
  } = {},
): Request {
  const headers = new Headers();
  if (options.apiKey !== undefined) {
    headers.set("apikey", options.apiKey);
  }
  if (options.authorization !== undefined) {
    headers.set("Authorization", options.authorization);
  }
  return new Request("http://localhost/functions/v1/recover-missions-v1", {
    method: options.method ?? "POST",
    headers,
    body: options.method === "GET"
      ? undefined
      : options.body === undefined
      ? undefined
      : JSON.stringify(options.body),
  });
}

function result(
  eventId: string,
  outcome: "PROCESSED" | "FAILED",
  completionsCreated = 0,
  rewardApplicationsCreated = 0,
): MissionRecoveryRow {
  return {
    event_id: eventId,
    outcome,
    completions_created: completionsCreated,
    reward_applications_created: rewardApplicationsCreated,
  };
}

function sequence(
  rows: Array<MissionRecoveryRow | null>,
): RecoverNextMissionEvent {
  return () => Promise.resolve({ row: rows.shift() ?? null, error: null });
}

Deno.test("validates POST before technical authorization", async () => {
  let authorizationCount = 0;
  let recoveryCount = 0;
  const handler = createMissionRecoveryHandler({
    authorize: () => {
      authorizationCount += 1;
      return true;
    },
    recoverNext: () => {
      recoveryCount += 1;
      return Promise.resolve({ row: null, error: null });
    },
  });

  const response = await handler(request({ method: "GET" }));

  equal(response.status, 405);
  equal(response.headers.get("allow"), "POST");
  equal(authorizationCount, 0);
  equal(recoveryCount, 0);
});

Deno.test("accepts only the named backend Secret API Key via apikey", async () => {
  const secretKeysPrevious = Deno.env.get("SUPABASE_SECRET_KEYS");
  const localSecretPrevious = Deno.env.get("SUPABASE_SECRET_KEY");
  const legacyPrevious = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const backendSecret = "sb_secret_backend_test_value";
  Deno.env.set(
    "SUPABASE_SECRET_KEYS",
    JSON.stringify({ bingo_backend: backendSecret }),
  );
  Deno.env.delete("SUPABASE_SECRET_KEY");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "legacy-service-role-test-value");
  try {
    let recoveryCount = 0;
    const handler = createMissionRecoveryHandler({
      recoverNext: () => {
        recoveryCount += 1;
        return Promise.resolve({ row: null, error: null });
      },
    });

    for (
      const candidate of [
        {},
        { apiKey: "sb_secret_wrong_test_value" },
        { authorization: "Bearer legacy-service-role-test-value" },
        {
          apiKey: "sb_secret_wrong_test_value",
          authorization: `Bearer ${backendSecret}`,
        },
      ] as const
    ) {
      const response = await handler(request(candidate));
      equal(response.status, 401);
      match(await response.text(), /^((?!sb_secret_|legacy-service-role).)*$/);
    }

    const authorized = await handler(request({
      apiKey: backendSecret,
      authorization: "Bearer ignored-legacy-token",
    }));
    equal(authorized.status, 200);
    match(await authorized.text(), /^((?!sb_secret_|legacy-service-role).)*$/);
    equal(recoveryCount, 1);
  } finally {
    if (secretKeysPrevious === undefined) {
      Deno.env.delete("SUPABASE_SECRET_KEYS");
    } else {
      Deno.env.set("SUPABASE_SECRET_KEYS", secretKeysPrevious);
    }
    if (localSecretPrevious === undefined) {
      Deno.env.delete("SUPABASE_SECRET_KEY");
    } else {
      Deno.env.set("SUPABASE_SECRET_KEY", localSecretPrevious);
    }
    if (legacyPrevious === undefined) {
      Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    } else {
      Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", legacyPrevious);
    }
  }
});

Deno.test("processes a small batch and continues after an event failure", async () => {
  const handler = createMissionRecoveryHandler({
    authorize: () => true,
    recoverNext: sequence([
      result(EVENT_A, "FAILED"),
      result(EVENT_B, "PROCESSED", 2, 3),
      null,
    ]),
  });

  const response = await handler(request({
    body: {
      event_id: "client-controlled",
      student_id: "client-controlled",
      reward: 999999,
    },
  }));

  equal(response.status, 200);
  deepStrictEqual(await response.json(), {
    events_examined: 2,
    processed: 1,
    failed: 1,
    completions_created: 2,
    reward_applications_created: 3,
    batch_limit_reached: false,
  });
});

Deno.test("repeated empty recovery is side-effect free", async () => {
  let callCount = 0;
  const handler = createMissionRecoveryHandler({
    authorize: () => true,
    recoverNext: () => {
      callCount += 1;
      return Promise.resolve({ row: null, error: null });
    },
  });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const response = await handler(request());
    equal(response.status, 200);
    equal(
      (await response.json() as { events_examined: number }).events_examined,
      0,
    );
  }
  equal(callCount, 2);
});

Deno.test("limits each manual invocation to ten independent transactions", async () => {
  let callCount = 0;
  const handler = createMissionRecoveryHandler({
    authorize: () => true,
    recoverNext: () => {
      callCount += 1;
      return Promise.resolve({
        row: result(crypto.randomUUID(), "PROCESSED"),
        error: null,
      });
    },
  });

  const response = await handler(request());
  const body = await response.json() as {
    events_examined: number;
    batch_limit_reached: boolean;
  };

  equal(response.status, 200);
  equal(callCount, 10);
  equal(body.events_examined, 10);
  equal(body.batch_limit_reached, true);
});

Deno.test("contains infrastructure failures without exposing database details", async () => {
  const handler = createMissionRecoveryHandler({
    authorize: () => true,
    recoverNext: () =>
      Promise.resolve({
        row: null,
        error: { code: "XX000", message: "secret SQL service_role stack" },
      }),
  });

  const response = await handler(request());
  const serialized = JSON.stringify(await response.json());

  equal(response.status, 500);
  match(serialized, /^((?!secret|SQL|service_role|stack).)*$/);
});
