import {
  type MachineAuthDependencies,
  withMachineAuthentication,
} from "../_shared/machine-auth.ts";
import { getSupabaseAdminClient } from "../_shared/supabase-admin.ts";

const SCOPE = "CENTRAL_BACKEND";

const PUBLIC_ERROR_MESSAGES = Object.freeze({
  METHOD_NOT_ALLOWED: "Método não permitido.",
  INTERNAL_ERROR: "Erro interno do servidor.",
});

export type CheckBackendReadiness = () => Promise<unknown>;

export type HealthHandlerDependencies = Readonly<{
  machineAuth?: MachineAuthDependencies;
  checkReadiness?: CheckBackendReadiness;
  now?: () => Date;
}>;

async function checkBackendReadinessServerSide(): Promise<unknown> {
  const { data, error } = await getSupabaseAdminClient().rpc(
    "check_backend_readiness_v1",
  );

  if (error !== null) {
    throw new Error("Backend readiness lookup failed.");
  }
  return data;
}

function responseHeaders(extra?: HeadersInit): Headers {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  return headers;
}

function operationalResponse(
  status: "AVAILABLE" | "UNAVAILABLE",
  checkedAt: string,
): Response {
  const available = status === "AVAILABLE";
  return Response.json(
    {
      status,
      can_start_deposit: available,
      scope: SCOPE,
      checked_at: checkedAt,
    },
    {
      status: available ? 200 : 503,
      headers: responseHeaders(),
    },
  );
}

function publicError(
  status: number,
  code: keyof typeof PUBLIC_ERROR_MESSAGES,
  headers?: HeadersInit,
): Response {
  return Response.json(
    { error: { code, message: PUBLIC_ERROR_MESSAGES[code] } },
    { status, headers: responseHeaders(headers) },
  );
}

async function handleAuthenticatedHealth(
  checkReadiness: CheckBackendReadiness,
  now: () => Date,
): Promise<Response> {
  let readiness: unknown;
  try {
    readiness = await checkReadiness();
  } catch {
    return publicError(500, "INTERNAL_ERROR");
  }

  if (typeof readiness !== "boolean") {
    return publicError(500, "INTERNAL_ERROR");
  }

  return operationalResponse(
    readiness ? "AVAILABLE" : "UNAVAILABLE",
    now().toISOString(),
  );
}

export function createHealthHandler(
  dependencies: HealthHandlerDependencies = {},
): (request: Request) => Promise<Response> {
  const checkReadiness = dependencies.checkReadiness ??
    checkBackendReadinessServerSide;
  const now = dependencies.now ?? (() => new Date());
  const authenticatedGet = withMachineAuthentication(
    () => handleAuthenticatedHealth(checkReadiness, now),
    dependencies.machineAuth,
  );

  return (request: Request): Promise<Response> => {
    if (request.method !== "GET") {
      return Promise.resolve(
        publicError(405, "METHOD_NOT_ALLOWED", { Allow: "GET" }),
      );
    }
    return authenticatedGet(request);
  };
}

export const handler = createHealthHandler();
