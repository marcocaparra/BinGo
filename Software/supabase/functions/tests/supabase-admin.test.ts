import { equal, throws } from "node:assert/strict";

import {
  BACKEND_SECRET_KEY_NAME,
  resolveBackendSecretKey,
} from "../_shared/supabase-admin.ts";

const HOSTED_KEY = "sb_secret_hosted_test_value";
const LOCAL_KEY = "sb_secret_local_test_value";
const CONFIGURATION_ERROR =
  "Edge Function server-side configuration is unavailable.";

function reader(
  values: Record<string, string | undefined>,
): (name: string) => string | undefined {
  return (name) => values[name];
}

Deno.test("resolves only the named bingo_backend key from hosted JSON", () => {
  const resolved = resolveBackendSecretKey(reader({
    SUPABASE_SECRET_KEYS: JSON.stringify({
      unrelated: "sb_secret_unrelated_test_value",
      [BACKEND_SECRET_KEY_NAME]: HOSTED_KEY,
    }),
    SUPABASE_SECRET_KEY: LOCAL_KEY,
    SUPABASE_SERVICE_ROLE_KEY: "legacy-service-role-test-value",
  }));

  equal(resolved, HOSTED_KEY);
});

Deno.test("fails closed when hosted JSON omits bingo_backend", () => {
  throws(
    () =>
      resolveBackendSecretKey(reader({
        SUPABASE_SECRET_KEYS: JSON.stringify({
          unrelated: "sb_secret_unrelated_test_value",
        }),
        SUPABASE_SECRET_KEY: LOCAL_KEY,
      })),
    new RegExp(CONFIGURATION_ERROR.replaceAll(".", "\\.")),
  );
});

Deno.test("fails closed for invalid hosted JSON", () => {
  throws(
    () =>
      resolveBackendSecretKey(reader({
        SUPABASE_SECRET_KEYS: "{invalid-json",
        SUPABASE_SECRET_KEY: LOCAL_KEY,
      })),
    new RegExp(CONFIGURATION_ERROR.replaceAll(".", "\\.")),
  );
});

Deno.test("fails closed for an invalid named secret value", () => {
  for (
    const invalidValue of [
      null,
      123,
      "",
      "service-role-test-value",
      " sb_secret_test_value",
    ]
  ) {
    throws(
      () =>
        resolveBackendSecretKey(reader({
          SUPABASE_SECRET_KEYS: JSON.stringify({
            [BACKEND_SECRET_KEY_NAME]: invalidValue,
          }),
        })),
      new RegExp(CONFIGURATION_ERROR.replaceAll(".", "\\.")),
    );
  }
});

Deno.test("uses the official local SUPABASE_SECRET_KEY fallback", () => {
  equal(
    resolveBackendSecretKey(reader({ SUPABASE_SECRET_KEY: LOCAL_KEY })),
    LOCAL_KEY,
  );
});

Deno.test("does not accept the legacy service-role variable as fallback", () => {
  throws(
    () =>
      resolveBackendSecretKey(reader({
        SUPABASE_SERVICE_ROLE_KEY: "legacy-service-role-test-value",
      })),
    new RegExp(CONFIGURATION_ERROR.replaceAll(".", "\\.")),
  );
});
