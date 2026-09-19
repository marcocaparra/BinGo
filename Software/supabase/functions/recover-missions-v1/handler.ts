import {
  getSupabaseAdminClient,
  resolveBackendSecretKey,
} from "../_shared/supabase-admin.ts";

const BATCH_SIZE = 10;

const PUBLIC_ERROR_MESSAGES = Object.freeze({
  METHOD_NOT_ALLOWED: "Método não permitido.",
  TECHNICAL_AUTHENTICATION_FAILED: "Credencial técnica inválida.",
  INTERNAL_ERROR: "Erro interno do servidor.",
});

export type MissionRecoveryRow = Readonly<{
  event_id: string;
  outcome: "PROCESSED" | "FAILED";
  completions_created: number;
  reward_applications_created: number;
}>;

type RpcError = Readonly<{ code?: string; message?: string }>;

export type RecoverNextMissionEvent = () => Promise<
  Readonly<{ row: MissionRecoveryRow | null; error: RpcError | null }>
>;

export type AuthorizeTechnicalRecovery = (
  request: Request,
) => boolean | Promise<boolean>;

export type MissionRecoveryHandlerDependencies = Readonly<{
  authorize?: AuthorizeTechnicalRecovery;
  recoverNext?: RecoverNextMissionEvent;
}>;

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) {
    return false;
  }

  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function authorizeBackendSecretKey(request: Request): boolean {
  const apiKey = request.headers.get("apikey");
  if (!apiKey) {
    return false;
  }

  return constantTimeEqual(apiKey, resolveBackendSecretKey());
}

async function recoverNextServerSide(): Promise<
  Readonly<{ row: MissionRecoveryRow | null; error: RpcError | null }>
> {
  const { data, error } = await getSupabaseAdminClient().rpc(
    "recover_next_mission_event_v1",
  );
  const rows = data as MissionRecoveryRow[] | null;
  return {
    row: Array.isArray(rows) && rows.length === 1 ? rows[0] : null,
    error,
  };
}

function publicError(
  status: number,
  code: keyof typeof PUBLIC_ERROR_MESSAGES,
  headers?: HeadersInit,
): Response {
  const responseHeaders = new Headers(headers);
  responseHeaders.set("Cache-Control", "no-store");
  return Response.json(
    { error: { code, message: PUBLIC_ERROR_MESSAGES[code] } },
    { status, headers: responseHeaders },
  );
}

function isRecoveryRow(
  row: MissionRecoveryRow | null,
): row is MissionRecoveryRow {
  return row !== null &&
    typeof row.event_id === "string" &&
    (row.outcome === "PROCESSED" || row.outcome === "FAILED") &&
    Number.isInteger(row.completions_created) &&
    row.completions_created >= 0 &&
    Number.isInteger(row.reward_applications_created) &&
    row.reward_applications_created >= 0;
}

export function createMissionRecoveryHandler(
  dependencies: MissionRecoveryHandlerDependencies = {},
): (request: Request) => Promise<Response> {
  const authorize = dependencies.authorize ?? authorizeBackendSecretKey;
  const recoverNext = dependencies.recoverNext ?? recoverNextServerSide;

  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return publicError(405, "METHOD_NOT_ALLOWED", { Allow: "POST" });
    }

    let authorized = false;
    try {
      authorized = await authorize(request);
    } catch {
      return publicError(500, "INTERNAL_ERROR");
    }
    if (!authorized) {
      return publicError(401, "TECHNICAL_AUTHENTICATION_FAILED");
    }

    let eventsExamined = 0;
    let processed = 0;
    let failed = 0;
    let completionsCreated = 0;
    let rewardApplicationsCreated = 0;

    for (let index = 0; index < BATCH_SIZE; index += 1) {
      let result: Awaited<ReturnType<RecoverNextMissionEvent>>;
      try {
        result = await recoverNext();
      } catch {
        return publicError(500, "INTERNAL_ERROR");
      }

      if (result.error !== null) {
        return publicError(500, "INTERNAL_ERROR");
      }
      if (result.row === null) {
        break;
      }
      if (!isRecoveryRow(result.row)) {
        return publicError(500, "INTERNAL_ERROR");
      }

      eventsExamined += 1;
      if (result.row.outcome === "PROCESSED") {
        processed += 1;
        completionsCreated += result.row.completions_created;
        rewardApplicationsCreated += result.row.reward_applications_created;
      } else {
        failed += 1;
      }
    }

    return Response.json(
      {
        events_examined: eventsExamined,
        processed,
        failed,
        completions_created: completionsCreated,
        reward_applications_created: rewardApplicationsCreated,
        batch_limit_reached: eventsExamined === BATCH_SIZE,
      },
      { status: 200, headers: { "Cache-Control": "no-store" } },
    );
  };
}

export const handler = createMissionRecoveryHandler();
