import {
  type MachineAuthDependencies,
  withMachineAuthentication,
} from "./machine-auth.ts";
import { getSupabaseAdminClient } from "./supabase-admin.ts";
import { verifyStudentPin } from "./student-pin.ts";

export type TotemOperation =
  | "context"
  | "student-pin"
  | "student-summary"
  | "rankings";
type Rpc = (
  name: string,
  args: Record<string, string>,
) => Promise<{ data: unknown; error: unknown }>;
export type TotemDependencies = {
  machineAuth?: MachineAuthDependencies;
  rpc?: Rpc;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const messages: Record<string, string> = {
  METHOD_NOT_ALLOWED: "Método não permitido.",
  INVALID_TOTEM_CONTRACT: "Dados de identificação inválidos.",
  TOTEM_CONTEXT_NOT_FOUND: "Contexto não encontrado nesta escola.",
  STUDENT_PIN_INVALID: "Não foi possível confirmar a identificação do aluno.",
};
function json(body: unknown, status = 200, extra?: HeadersInit): Response {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  return Response.json(body, { status, headers });
}
function error(status: number, code: string, headers?: HeadersInit): Response {
  return json({ error: { code, message: messages[code] } }, status, headers);
}
const serverRpc: Rpc = async (name, args) => {
  const { data, error } = await getSupabaseAdminClient().rpc(name, args);
  return { data, error };
};

export function createTotemHandler(
  operation: TotemOperation,
  dependencies: TotemDependencies = {},
) {
  const method = operation === "context" || operation === "rankings"
    ? "GET"
    : "POST";
  const rpc = dependencies.rpc ?? serverRpc;
  const authenticated = withMachineAuthentication(async (request, machine) => {
    // School and machine authority never come from query strings or JSON.
    if (new URL(request.url).search) {
      return error(422, "INVALID_TOTEM_CONTRACT");
    }
    const args: Record<string, string> = { p_machine_id: machine.id };
    let pin = "";
    if (method === "POST") {
      let body: Record<string, unknown>;
      try {
        const raw = await request.text();
        if (
          raw.length > 4096 ||
          !request.headers.get("content-type")?.startsWith("application/json")
        ) throw new Error();
        body = JSON.parse(raw);
        if (!body || typeof body !== "object" || Array.isArray(body)) {
          throw new Error();
        }
      } catch {
        return error(422, "INVALID_TOTEM_CONTRACT");
      }
      const keys = operation === "student-pin"
        ? ["class_id", "student_id", "pin"]
        : ["student_id"];
      if (
        Object.keys(body).length !== keys.length ||
        keys.some((key) => typeof body[key] !== "string")
      ) return error(422, "INVALID_TOTEM_CONTRACT");
      if (!uuid.test(body.student_id as string)) {
        return error(422, "INVALID_TOTEM_CONTRACT");
      }
      args.p_student_id = body.student_id as string;
      if (operation === "student-pin") {
        pin = body.pin as string;
        if (!uuid.test(body.class_id as string) || !/^[0-9]{4}$/.test(pin)) {
          return error(422, "INVALID_TOTEM_CONTRACT");
        }
        args.p_class_id = body.class_id as string;
      }
    }
    const rpcName = operation === "student-pin"
      ? "get_totem_student_pin_record_v1"
      : `get_totem_${operation.replaceAll("-", "_")}_v1`;
    const result = await rpc(rpcName, args);
    if (result.error) throw new Error("Totem read failed");
    if (operation === "student-pin") {
      const record = result.data as {
        pin_hash?: unknown;
        student?: Record<string, unknown>;
      } | null;
      if (
        !record || typeof record.pin_hash !== "string" ||
        !await verifyStudentPin(pin, record.pin_hash)
      ) return error(401, "STUDENT_PIN_INVALID");
      const student = record.student;
      if (
        !student ||
        ["id", "name", "class_id", "class_name"].some((key) =>
          typeof student[key] !== "string"
        )
      ) throw new Error("Invalid PIN context");
      // Explicit projection: never return the hash, Auth UUID, PIN or JWT.
      return json({
        confirmed: true,
        student: {
          id: student.id,
          name: student.name,
          class_id: student.class_id,
          class_name: student.class_name,
        },
      });
    }
    if (result.data === null) return error(404, "TOTEM_CONTEXT_NOT_FOUND");
    if (
      !result.data || typeof result.data !== "object" ||
      Array.isArray(result.data)
    ) throw new Error("Invalid Totem response");
    return json(result.data);
  }, dependencies.machineAuth);
  return (request: Request): Promise<Response> =>
    request.method === method
      ? authenticated(request)
      : Promise.resolve(error(405, "METHOD_NOT_ALLOWED", { Allow: method }));
}
