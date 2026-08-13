import { getSupabaseAdminClient } from "./supabase-admin.ts";

const MACHINE_ID_HEADER = "X-Machine-Id";
const API_KEY_HEADER = "X-Api-Key";
const PBKDF2_ITERATIONS = 120_000;
const SHA256_BYTES = 32;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BASE64_PATTERN =
  /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

const AUTHENTICATION_ERROR_BODY = Object.freeze({
  error: Object.freeze({
    code: "MACHINE_AUTHENTICATION_FAILED",
    message: "Credenciais técnicas inválidas.",
  }),
});

const INTERNAL_ERROR_BODY = Object.freeze({
  error: Object.freeze({
    code: "INTERNAL_ERROR",
    message: "Erro interno do servidor.",
  }),
});

type MachineCredentialRow = Readonly<{
  id: string;
  school_id: string;
  api_key_hash: string | null;
}>;

export type TrustedMachineIdentity = Readonly<{
  id: string;
  schoolId: string;
}>;

export type MachineLookup = (
  machineId: string,
) => Promise<MachineCredentialRow | null>;

export type MachineAuthDependencies = Readonly<{
  lookupMachine?: MachineLookup;
}>;

export type MachineAuthenticatedHandler = (
  request: Request,
  machine: TrustedMachineIdentity,
) => Response | Promise<Response>;

class MachineAuthenticationError extends Error {
  constructor() {
    super("Machine authentication failed.");
    this.name = "MachineAuthenticationError";
  }
}

function jsonError(
  status: number,
  body: typeof AUTHENTICATION_ERROR_BODY | typeof INTERNAL_ERROR_BODY,
): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}

async function lookupMachineServerSide(
  machineId: string,
): Promise<MachineCredentialRow | null> {
  const { data, error } = await getSupabaseAdminClient()
    .from("machines")
    .select("id, school_id, api_key_hash")
    .eq("id", machineId)
    .maybeSingle();

  if (error) {
    throw new Error("Machine credential lookup failed.");
  }

  return data as MachineCredentialRow | null;
}

function decodeBase64(value: string): Uint8Array | null {
  if (!value || !BASE64_PATTERN.test(value)) {
    return null;
  }

  try {
    const decoded = atob(value);
    const bytes = new Uint8Array(decoded.length);
    for (let index = 0; index < decoded.length; index += 1) {
      bytes[index] = decoded.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }

  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

async function verifyApiKey(
  apiKey: string,
  storedHash: string,
): Promise<boolean> {
  const parts = storedHash.split("$");
  if (parts.length !== 2) {
    return false;
  }

  const salt = decodeBase64(parts[0]);
  const expectedDigest = decodeBase64(parts[1]);
  if (!salt?.length || expectedDigest?.length !== SHA256_BYTES) {
    return false;
  }

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiKey),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const saltBuffer = new ArrayBuffer(salt.byteLength);
  new Uint8Array(saltBuffer).set(salt);
  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt: saltBuffer,
      iterations: PBKDF2_ITERATIONS,
    },
    keyMaterial,
    SHA256_BYTES * 8,
  );

  return constantTimeEqual(new Uint8Array(derivedBits), expectedDigest);
}

export async function authenticateMachine(
  request: Request,
  dependencies: MachineAuthDependencies = {},
): Promise<TrustedMachineIdentity> {
  const machineId = request.headers.get(MACHINE_ID_HEADER);
  const apiKey = request.headers.get(API_KEY_HEADER);

  if (
    machineId === null || !UUID_PATTERN.test(machineId) || apiKey === null ||
    apiKey.length === 0
  ) {
    throw new MachineAuthenticationError();
  }

  const lookupMachine = dependencies.lookupMachine ?? lookupMachineServerSide;
  const machine = await lookupMachine(machineId);
  if (
    machine === null || typeof machine.api_key_hash !== "string" ||
    machine.api_key_hash.length === 0
  ) {
    throw new MachineAuthenticationError();
  }

  const isValid = await verifyApiKey(apiKey, machine.api_key_hash);
  if (!isValid) {
    throw new MachineAuthenticationError();
  }

  return Object.freeze({
    id: machine.id,
    schoolId: machine.school_id,
  });
}

export function withMachineAuthentication(
  handler: MachineAuthenticatedHandler,
  dependencies: MachineAuthDependencies = {},
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    try {
      const machine = await authenticateMachine(request, dependencies);
      return await handler(request, machine);
    } catch (error) {
      if (error instanceof MachineAuthenticationError) {
        return jsonError(401, AUTHENTICATION_ERROR_BODY);
      }
      return jsonError(500, INTERNAL_ERROR_BODY);
    }
  };
}
