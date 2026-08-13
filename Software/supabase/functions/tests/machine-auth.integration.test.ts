import { deepStrictEqual } from "node:assert/strict";

import { authenticateMachine } from "../_shared/machine-auth.ts";

const integrationEnabled = Deno.env.get("BINGO_EDGE_AUTH_INTEGRATION") === "1";

Deno.test({
  name: "authenticates the seeded machine through the local Supabase Data API",
  ignore: !integrationEnabled,
  async fn() {
    const machineId = requireEnvironment("BINGO_EDGE_TEST_MACHINE_ID");
    const apiKey = requireEnvironment("BINGO_EDGE_TEST_API_KEY");
    const expectedSchoolId = requireEnvironment("BINGO_EDGE_TEST_SCHOOL_ID");
    const request = new Request(
      "http://localhost/functions/v1/future-function",
      {
        headers: {
          "X-Machine-Id": machineId,
          "X-Api-Key": apiKey,
        },
      },
    );

    const identity = await authenticateMachine(request);

    deepStrictEqual(identity, {
      id: machineId,
      schoolId: expectedSchoolId,
    });
    if (!Object.isFrozen(identity)) {
      throw new Error("Trusted machine identity must be immutable.");
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
