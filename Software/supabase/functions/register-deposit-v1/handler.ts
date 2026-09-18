import {
  type MachineAuthDependencies,
  type TrustedMachineIdentity,
  withMachineAuthentication,
} from "../_shared/machine-auth.ts";
import { getSupabaseAdminClient } from "../_shared/supabase-admin.ts";
import { publicError } from "./errors.ts";
import { type DepositRequestBody, parseDepositRequestBody } from "./schema.ts";

const CATEGORY_NOT_FOUND_MESSAGE =
  "Categoria de lixo eletronico inexistente ou inativa.";

export type RegisterDepositRpcRow = Readonly<{
  deposit_id: string;
  event_id: string;
  waste_category_code: string | null;
  category_source: string | null;
  bonus_rate_applied: string | number;
  bonus_bincoins_awarded: number;
  points_awarded_student: number;
  points_awarded_class: number;
  created_at: string;
  was_replayed: boolean;
}>;

export type RegisterDepositRpcError = Readonly<{
  code?: string;
  message?: string;
}>;

export type RegisterDeposit = (
  body: DepositRequestBody,
  machine: TrustedMachineIdentity,
) => Promise<
  Readonly<
    { row: RegisterDepositRpcRow | null; error: RegisterDepositRpcError | null }
  >
>;

export type ProcessMissionEvent = (
  eventId: string,
) => Promise<Readonly<{ error: RegisterDepositRpcError | null }>>;

export type RecordMissionProcessingFailure = (
  eventId: string,
) => Promise<Readonly<{ error: RegisterDepositRpcError | null }>>;

export type RegisterDepositHandlerDependencies = Readonly<{
  machineAuth?: MachineAuthDependencies;
  registerDeposit?: RegisterDeposit;
  processMissionEvent?: ProcessMissionEvent;
  recordMissionProcessingFailure?: RecordMissionProcessingFailure;
}>;

async function registerDepositServerSide(
  body: DepositRequestBody,
  machine: TrustedMachineIdentity,
): Promise<
  Readonly<
    { row: RegisterDepositRpcRow | null; error: RegisterDepositRpcError | null }
  >
> {
  const { data, error } = await getSupabaseAdminClient().rpc(
    "register_deposit_v1",
    {
      p_event_id: body.event_id,
      p_machine_id: machine.id,
      p_class_id: body.class_id,
      p_is_valid: body.is_valid,
      p_student_id: body.student_id,
      p_detected_type: body.detected_type,
      p_waste_category_code: body.waste_category_code,
      p_category_source: body.category_source,
    },
  );

  const rows = data as RegisterDepositRpcRow[] | null;
  return {
    row: Array.isArray(rows) && rows.length === 1 ? rows[0] : null,
    error,
  };
}

async function processMissionEventServerSide(
  eventId: string,
): Promise<Readonly<{ error: RegisterDepositRpcError | null }>> {
  const { error } = await getSupabaseAdminClient().rpc(
    "process_mission_event_v1",
    { p_event_id: eventId },
  );
  return { error };
}

async function recordMissionProcessingFailureServerSide(
  eventId: string,
): Promise<Readonly<{ error: RegisterDepositRpcError | null }>> {
  const { error } = await getSupabaseAdminClient().rpc(
    "record_mission_processing_failure_v1",
    { p_event_id: eventId },
  );
  return { error };
}

async function attemptMissionProcessing(
  eventId: string,
  processMissionEvent: ProcessMissionEvent,
  recordMissionProcessingFailure: RecordMissionProcessingFailure,
): Promise<void> {
  let failed = false;
  try {
    const result = await processMissionEvent(eventId);
    failed = result.error !== null;
  } catch {
    failed = true;
  }

  if (!failed) {
    return;
  }

  // Esta chamada abre uma nova transacao depois do rollback economico. O
  // erro bruto nunca e encaminhado nem persistido; a RPC grava apenas o
  // codigo operacional sanitizado definido no banco.
  try {
    await recordMissionProcessingFailure(eventId);
  } catch {
    // A resposta do descarte confirmado continua sendo prioritaria. A linha
    // pendente permanece recuperavel mesmo se este registro operacional falhar.
  }
}

function isRpcRow(
  row: RegisterDepositRpcRow | null,
): row is RegisterDepositRpcRow {
  return row !== null &&
    typeof row.deposit_id === "string" &&
    typeof row.event_id === "string" &&
    (typeof row.waste_category_code === "string" ||
      row.waste_category_code === null) &&
    (typeof row.category_source === "string" || row.category_source === null) &&
    (typeof row.bonus_rate_applied === "string" ||
      typeof row.bonus_rate_applied === "number") &&
    typeof row.bonus_bincoins_awarded === "number" &&
    typeof row.points_awarded_student === "number" &&
    typeof row.points_awarded_class === "number" &&
    typeof row.created_at === "string" &&
    typeof row.was_replayed === "boolean";
}

function translateRpcError(error: RegisterDepositRpcError): Response {
  if (error.code === "23505") {
    return publicError(409, "EVENT_ID_CONFLICT");
  }
  if (error.code === "23503") {
    return publicError(404, "DEPOSIT_CONTEXT_NOT_FOUND");
  }
  if (error.code === "23514") {
    return publicError(422, "INVALID_DEPOSIT_CONTRACT");
  }
  if (
    error.code === "P0002" && error.message === CATEGORY_NOT_FOUND_MESSAGE
  ) {
    return publicError(404, "WASTE_CATEGORY_NOT_FOUND");
  }
  return publicError(500, "INTERNAL_ERROR");
}

async function handleAuthenticatedPost(
  request: Request,
  machine: TrustedMachineIdentity,
  registerDeposit: RegisterDeposit,
  processMissionEvent: ProcessMissionEvent,
  recordMissionProcessingFailure: RecordMissionProcessingFailure,
): Promise<Response> {
  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0]
    .trim().toLowerCase();
  if (contentType !== "application/json") {
    return publicError(422, "INVALID_DEPOSIT_CONTRACT");
  }

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return publicError(422, "INVALID_DEPOSIT_CONTRACT");
  }

  const body = parseDepositRequestBody(rawBody);
  if (body === null) {
    return publicError(422, "INVALID_DEPOSIT_CONTRACT");
  }

  let result: Awaited<ReturnType<RegisterDeposit>>;
  try {
    result = await registerDeposit(body, machine);
  } catch {
    return publicError(500, "INTERNAL_ERROR");
  }

  if (result.error !== null) {
    return translateRpcError(result.error);
  }
  if (!isRpcRow(result.row)) {
    return publicError(500, "INTERNAL_ERROR");
  }

  const row = result.row;
  await attemptMissionProcessing(
    row.event_id,
    processMissionEvent,
    recordMissionProcessingFailure,
  );

  return Response.json(
    {
      id: row.deposit_id,
      event_id: row.event_id,
      waste_category_code: row.waste_category_code,
      category_source: row.category_source,
      bonus_rate_applied: row.bonus_rate_applied,
      bonus_bincoins_awarded: row.bonus_bincoins_awarded,
      points_awarded_student: row.points_awarded_student,
      points_awarded_class: row.points_awarded_class,
      created_at: row.created_at,
    },
    {
      status: row.was_replayed ? 200 : 201,
      headers: { "Cache-Control": "no-store" },
    },
  );
}

export function createRegisterDepositHandler(
  dependencies: RegisterDepositHandlerDependencies = {},
): (request: Request) => Promise<Response> {
  const registerDeposit = dependencies.registerDeposit ??
    registerDepositServerSide;
  const processMissionEvent = dependencies.processMissionEvent ??
    processMissionEventServerSide;
  const recordMissionProcessingFailure =
    dependencies.recordMissionProcessingFailure ??
      recordMissionProcessingFailureServerSide;
  const authenticatedPost = withMachineAuthentication(
    (request, machine) =>
      handleAuthenticatedPost(
        request,
        machine,
        registerDeposit,
        processMissionEvent,
        recordMissionProcessingFailure,
      ),
    dependencies.machineAuth,
  );

  return (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return Promise.resolve(
        publicError(405, "METHOD_NOT_ALLOWED", { Allow: "POST" }),
      );
    }
    return authenticatedPost(request);
  };
}

export const handler = createRegisterDepositHandler();
