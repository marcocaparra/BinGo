import { deepStrictEqual, equal, ok } from "node:assert/strict";
import {
  createTotemHandler,
  type TotemOperation,
} from "../_shared/totem-handler.ts";
import { verifyStudentPin } from "../_shared/student-pin.ts";

const machineId = "40000000-0000-4000-8000-000000000001";
const schoolId = "10000000-0000-4000-8000-000000000001";
const studentId = "30000000-0000-4000-8000-000000000001";
const classId = "20000000-0000-4000-8000-000000000001";
const machineHash =
  "YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI=";
const pinHash =
  "cyFk4kdbNFaq5m+omkVohA==$SyR/dsE76yHMsMaw6mO+L7hYBOqChGqbh7ZSID20Wys=";
const student = {
  id: studentId,
  name: "Ana",
  class_id: classId,
  class_name: "6 A",
};
const pinBody = { student_id: studentId, class_id: classId, pin: "4827" };
function request(
  operation: TotemOperation,
  body?: unknown,
  key = "edge-demo-key",
  query = "",
) {
  return new Request(
    `http://localhost/functions/v1/totem-${operation}-v1${query}`,
    {
      method: ["context", "rankings"].includes(operation) ? "GET" : "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Machine-Id": machineId,
        "X-Api-Key": key,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    },
  );
}
function dependencies(
  data: unknown,
  capture: (name: string, args: Record<string, string>) => void = () => {},
) {
  return {
    machineAuth: {
      lookupMachine: () =>
        Promise.resolve({
          id: machineId,
          school_id: schoolId,
          api_key_hash: machineHash,
        }),
    },
    rpc: (name: string, args: Record<string, string>) => {
      capture(name, args);
      return Promise.resolve({ data, error: null });
    },
  };
}
Deno.test("PIN uses legacy PBKDF2 without changing hashes", async () => {
  equal(await verifyStudentPin("4827", pinHash), true);
  for (const pin of ["0000", "482", "48270", " 4827", "４８２７"]) {
    equal(await verifyStudentPin(pin, pinHash), false);
  }
  for (const hash of ["", "bad", "a$b$c", "!$!", "YQ==$Yg=="]) {
    equal(await verifyStudentPin("4827", hash), false);
  }
});
Deno.test("PIN confirmation contains public identity only, never JWT or hash", async () => {
  const handler = createTotemHandler(
    "student-pin",
    dependencies({
      student: { ...student, auth_user_id: "private" },
      pin_hash: pinHash,
    }, (name, args) => {
      equal(name, "get_totem_student_pin_record_v1");
      deepStrictEqual(args, {
        p_machine_id: machineId,
        p_student_id: studentId,
        p_class_id: classId,
      });
    }),
  );
  const response = await handler(request("student-pin", pinBody));
  equal(response.status, 200);
  deepStrictEqual(await response.json(), { confirmed: true, student });
  equal(response.headers.get("cache-control"), "no-store");
  equal(response.headers.has("access-control-allow-origin"), false);
});
for (const record of [null, { pin_hash: null }, { student, pin_hash: "bad" }]) {
  Deno.test(`PIN absent/inactive/outside scope fails closed (${JSON.stringify(record)})`, async () => {
    equal(
      (await createTotemHandler("student-pin", dependencies(record))(
        request("student-pin", pinBody),
      )).status,
      401,
    );
  });
}
Deno.test("Incorrect PIN gets sanitized failure without reflecting PIN", async () => {
  const response = await createTotemHandler(
    "student-pin",
    dependencies({ student, pin_hash: pinHash }),
  )(request("student-pin", { ...pinBody, pin: "1234" }));
  equal(response.status, 401);
  ok(!(await response.text()).includes("1234"));
});
for (
  const body of [
    { ...pinBody, school_id: schoolId },
    { ...pinBody, student_id: "wrong" },
    { ...pinBody, class_id: "wrong" },
    { ...pinBody, pin: "abc1" },
    null,
    [pinBody],
  ]
) {
  Deno.test(`PIN rejects invalid or extra fields (${JSON.stringify(body)})`, async () => {
    equal(
      (await createTotemHandler(
        "student-pin",
        dependencies(null, () => {
          throw new Error("Must not call RPC");
        }),
      )(request("student-pin", body))).status,
      422,
    );
  });
}
for (
  const operation of [
    "context",
    "student-pin",
    "student-summary",
    "rankings",
  ] as const
) {
  Deno.test(`${operation} requires machine auth; never executes RPC for bad key`, async () => {
    const handler = createTotemHandler(
      operation,
      dependencies({}, () => {
        throw new Error("Must not call RPC");
      }),
    );
    const body = operation === "student-pin"
      ? pinBody
      : operation === "student-summary"
      ? { student_id: studentId }
      : undefined;
    equal((await handler(request(operation, body, "wrong-key"))).status, 401);
    equal(
      (await handler(
        request(operation, body, "edge-demo-key", `?school_id=${schoolId}`),
      )).status,
      422,
    );
    equal(
      (await handler(new Request("http://localhost", { method: "DELETE" })))
        .status,
      405,
    );
  });
}
for (const operation of ["context", "rankings", "student-summary"] as const) {
  Deno.test(`${operation} calls only scoped server RPC and returns real snapshot`, async () => {
    const snapshot = { school: { id: schoolId }, students: [], classes: [] };
    const handler = createTotemHandler(
      operation,
      dependencies(snapshot, (name, args) => {
        equal(name, `get_totem_${operation.replaceAll("-", "_")}_v1`);
        deepStrictEqual(
          args,
          operation === "student-summary"
            ? { p_machine_id: machineId, p_student_id: studentId }
            : { p_machine_id: machineId },
        );
      }),
    );
    const response = await handler(
      request(
        operation,
        operation === "student-summary" ? { student_id: studentId } : undefined,
      ),
    );
    equal(response.status, 200);
    deepStrictEqual(await response.json(), snapshot);
  });
}
Deno.test("Missing summary is 404; backend errors are sanitized 500", async () => {
  equal(
    (await createTotemHandler("student-summary", dependencies(null))(
      request("student-summary", { student_id: studentId }),
    )).status,
    404,
  );
  const handler = createTotemHandler("context", {
    ...dependencies(null),
    rpc: () => Promise.resolve({ data: null, error: { secret: "private" } }),
  });
  const response = await handler(request("context"));
  equal(response.status, 500);
  ok(!(await response.text()).includes("private"));
});
