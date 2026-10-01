import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let adminClient: SupabaseClient | undefined;

export const BACKEND_SECRET_KEY_NAME = "bingo_backend";

type EnvironmentReader = (name: string) => string | undefined;

function isSecretApiKey(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > "sb_secret_".length &&
    value.startsWith("sb_secret_") &&
    value.trim() === value;
}

export function resolveBackendSecretKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): string {
  const hostedSecretKeys = readEnvironment("SUPABASE_SECRET_KEYS");
  if (hostedSecretKeys !== undefined) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(hostedSecretKeys);
    } catch {
      throw new Error(
        "Edge Function server-side configuration is unavailable.",
      );
    }

    // Supabase CLI's local HTTP worker injects only the name "default" and
    // refuses SUPABASE_* overrides. Accept that key exclusively on its Docker
    // loopback gateway; hosted runtimes still require bingo_backend.
    if (
      readEnvironment("SUPABASE_URL") === "http://kong:8000" &&
      parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) &&
      !Object.hasOwn(parsed, BACKEND_SECRET_KEY_NAME) &&
      Object.hasOwn(parsed, "default") &&
      isSecretApiKey((parsed as Record<string, unknown>).default)
    ) {
      return (parsed as Record<string, string>).default;
    }

    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed) ||
      !Object.hasOwn(parsed, BACKEND_SECRET_KEY_NAME)
    ) {
      throw new Error(
        "Edge Function server-side configuration is unavailable.",
      );
    }

    const namedSecret = (parsed as Record<string, unknown>)[
      BACKEND_SECRET_KEY_NAME
    ];
    if (!isSecretApiKey(namedSecret)) {
      throw new Error(
        "Edge Function server-side configuration is unavailable.",
      );
    }
    return namedSecret;
  }

  const localSecretKey = readEnvironment("SUPABASE_SECRET_KEY");
  if (!isSecretApiKey(localSecretKey)) {
    throw new Error("Edge Function server-side configuration is unavailable.");
  }
  return localSecretKey;
}

export function getSupabaseAdminClient(): SupabaseClient {
  if (adminClient !== undefined) {
    return adminClient;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const secretKey = resolveBackendSecretKey();

  if (!supabaseUrl) {
    throw new Error("Edge Function server-side configuration is unavailable.");
  }

  adminClient = createClient(supabaseUrl, secretKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });

  return adminClient;
}
