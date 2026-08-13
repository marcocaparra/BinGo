import { deepStrictEqual, equal, match } from "node:assert/strict";

import {
  type MachineLookup,
  withMachineAuthentication,
} from "../_shared/machine-auth.ts";

const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const SCHOOL_ID = "10000000-0000-4000-8000-000000000001";
const UNKNOWN_MACHINE_ID = "49999999-9999-4999-8999-999999999999";
const DEMO_API_KEY = "edge-demo-key";
const DEMO_API_KEY_HASH =
  "YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI=";

const AUTHENTICATION_ERROR = {
  error: {
    code: "MACHINE_AUTHENTICATION_FAILED",
    message: "Credenciais técnicas inválidas.",
  },
};

function machineRow() {
  return {
    id: MACHINE_ID,
    school_id: SCHOOL_ID,
    api_key_hash: DEMO_API_KEY_HASH,
  };
}

function requestWithHeaders(
  machineId: string | null,
  apiKey: string | null,
  body?: Record<string, unknown>,
): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (machineId !== null) {
    headers.set("X-Machine-Id", machineId);
  }
  if (apiKey !== null) {
    headers.set("X-Api-Key", apiKey);
  }

  return new Request("http://localhost/functions/v1/future-function", {
    method: "POST",
    headers,
    body: JSON.stringify(body ?? {}),
  });
}

async function responseBody(response: Response): Promise<unknown> {
  return await response.json();
}

function authenticatedHandler(lookupMachine: MachineLookup) {
  return withMachineAuthentication(
    async (request, machine) => {
      const body = await request.json();
      return Response.json({ machine, body });
    },
    { lookupMachine },
  );
}

Deno.test("accepts the current demo credential and returns only trusted identity", async () => {
  const lookupMachine: MachineLookup = (machineId) => {
    equal(machineId, MACHINE_ID);
    return Promise.resolve(machineRow());
  };
  const handler = authenticatedHandler(lookupMachine);
  const response = await handler(
    requestWithHeaders(MACHINE_ID, DEMO_API_KEY, {
      machine_id: UNKNOWN_MACHINE_ID,
      school_id: "19999999-9999-4999-8999-999999999999",
    }),
  );

  equal(response.status, 200);
  const body = await responseBody(response);
  deepStrictEqual(body, {
    machine: { id: MACHINE_ID, schoolId: SCHOOL_ID },
    body: {
      machine_id: UNKNOWN_MACHINE_ID,
      school_id: "19999999-9999-4999-8999-999999999999",
    },
  });
  equal(JSON.stringify(body).includes("api_key_hash"), false);
});

Deno.test("returns the same 401 when either technical header is absent", async () => {
  let lookupCount = 0;
  const lookupMachine: MachineLookup = () => {
    lookupCount += 1;
    return Promise.resolve(machineRow());
  };
  const handler = authenticatedHandler(lookupMachine);

  for (
    const request of [
      requestWithHeaders(null, DEMO_API_KEY),
      requestWithHeaders(MACHINE_ID, null),
    ]
  ) {
    const response = await handler(request);
    equal(response.status, 401);
    deepStrictEqual(await responseBody(response), AUTHENTICATION_ERROR);
    equal(response.headers.get("cache-control"), "no-store");
  }
  equal(lookupCount, 0);
});

Deno.test("makes an unknown machine and an invalid key indistinguishable", async () => {
  const lookupMachine: MachineLookup = (machineId) =>
    Promise.resolve(machineId === MACHINE_ID ? machineRow() : null);
  const handler = authenticatedHandler(lookupMachine);

  const invalidKeyResponse = await handler(
    requestWithHeaders(MACHINE_ID, "wrong-key"),
  );
  const unknownMachineResponse = await handler(
    requestWithHeaders(UNKNOWN_MACHINE_ID, DEMO_API_KEY),
  );

  equal(invalidKeyResponse.status, 401);
  equal(unknownMachineResponse.status, 401);
  deepStrictEqual(await responseBody(invalidKeyResponse), AUTHENTICATION_ERROR);
  deepStrictEqual(
    await responseBody(unknownMachineResponse),
    AUTHENTICATION_ERROR,
  );
});

Deno.test("rejects a malformed machine id without querying the database", async () => {
  let lookupCount = 0;
  const handler = authenticatedHandler(() => {
    lookupCount += 1;
    return Promise.resolve(machineRow());
  });

  const response = await handler(
    requestWithHeaders("not-a-uuid", DEMO_API_KEY),
  );

  equal(response.status, 401);
  deepStrictEqual(await responseBody(response), AUTHENTICATION_ERROR);
  equal(lookupCount, 0);
});

Deno.test("compares an API key literally when the header adapter preserves whitespace", async () => {
  const handler = withMachineAuthentication(
    () => Response.json({ authenticated: true }),
    { lookupMachine: () => Promise.resolve(machineRow()) },
  );

  const leadingSpace = await handler(
    requestWithLiteralApiKey(` ${DEMO_API_KEY}`),
  );
  const trailingSpace = await handler(
    requestWithLiteralApiKey(`${DEMO_API_KEY} `),
  );

  equal(leadingSpace.status, 401);
  equal(trailingSpace.status, 401);
  deepStrictEqual(await responseBody(leadingSpace), AUTHENTICATION_ERROR);
  deepStrictEqual(await responseBody(trailingSpace), AUTHENTICATION_ERROR);
});

Deno.test("does not expose infrastructure failures", async () => {
  const handler = authenticatedHandler(() =>
    Promise.reject(new Error("sensitive PostgREST details"))
  );

  const response = await handler(requestWithHeaders(MACHINE_ID, DEMO_API_KEY));
  const serializedBody = JSON.stringify(await responseBody(response));

  equal(response.status, 500);
  deepStrictEqual(JSON.parse(serializedBody), {
    error: { code: "INTERNAL_ERROR", message: "Erro interno do servidor." },
  });
  match(
    serializedBody,
    /^((?!sensitive|PostgREST|service_role|api_key_hash).)*$/,
  );
});

function requestWithLiteralApiKey(apiKey: string): Request {
  return {
    headers: {
      get(name: string): string | null {
        if (name === "X-Machine-Id") {
          return MACHINE_ID;
        }
        if (name === "X-Api-Key") {
          return apiKey;
        }
        return null;
      },
    },
  } as unknown as Request;
}
