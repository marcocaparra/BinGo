import { deepStrictEqual, equal, ok } from "node:assert/strict";
import postgres from "postgres";
const enabled = Deno.env.get("BINGO_EDGE_TOTEM_INTEGRATION") === "1";
const machineId = "40000000-0000-4000-8000-000000000001";
const classId = "20000000-0000-4000-8000-000000000001";
const studentId = "30000000-0000-4000-8000-000000000001";
async function call(operation: string, body?: unknown, key = "edge-demo-key") {
  return await fetch(`http://127.0.0.1:54321/functions/v1/${operation}`, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Machine-Id": machineId,
      "X-Api-Key": key,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
Deno.test({
  name:
    "real local HTTP machine → readiness → context/PIN/summary/rankings → deposit/replay/class-only",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const url = Deno.env.get("BINGO_EDGE_TEST_DATABASE_URL");
    if (!url || !["127.0.0.1", "localhost"].includes(new URL(url).hostname)) {
      throw new Error("Local DB required");
    }
    const sql = postgres(url, { max: 1, prepare: false });
    const events = [
      crypto.randomUUID(),
      crypto.randomUUID(),
      crypto.randomUUID(),
    ];
    const [beforeStudent] =
      await sql`select points_student_balance from students where id=${studentId}`;
    const [beforeClass] =
      await sql`select points_class_balance from classes where id=${classId}`;
    const [beforeState] =
      await sql`select status, is_activated from students where id=${studentId}`;
    const [beforeMachine] =
      await sql`select status from machines where id=${machineId}`;
    try {
      for (const op of ["health-v1", "totem-context-v1", "totem-rankings-v1"]) {
        const rejected = await call(op, undefined, "wrong-key");
        equal(rejected.status, 401);
        await rejected.body?.cancel();
      }
      const health = await call("health-v1");
      equal(health.status, 200);
      equal((await health.json()).can_start_deposit, true);
      const contextResponse = await call("totem-context-v1");
      equal(contextResponse.status, 200);
      const context = await contextResponse.json();
      equal(context.school.id, "10000000-0000-4000-8000-000000000001");
      ok(context.students.some((s: { id: string }) => s.id === studentId));
      for (
        const secret of [
          "pin_hash",
          "auth_user_id",
          "email",
          "registration",
          "api_key",
        ]
      ) ok(!JSON.stringify(context).includes(secret));
      await sql`update students set is_activated=false where id=${studentId}`;
      await sql`update machines set status='OFFLINE' where id=${machineId}`;
      const pin = { class_id: classId, student_id: studentId, pin: "4827" };
      const validPin = await call("totem-student-pin-v1", pin);
      equal(validPin.status, 200);
      const identity = await validPin.json();
      equal(identity.confirmed, true);
      equal(identity.student.id, studentId);
      ok(!JSON.stringify(identity).includes("4827"));
      equal(Object.keys(identity).length, 2);
      for (
        const invalid of [{ ...pin, pin: "0000" }, {
          ...pin,
          class_id: "20000000-0000-4000-8000-000000000002",
        }]
      ) {
        const response = await call("totem-student-pin-v1", invalid);
        equal(response.status, 401);
        await response.body?.cancel();
      }
      await sql`update students set status='INACTIVE' where id=${studentId}`;
      const inactive = await call("totem-student-pin-v1", pin);
      equal(inactive.status, 401);
      await inactive.body?.cancel();
      const inactiveContext = await (await call("totem-context-v1")).json();
      ok(
        !inactiveContext.students.some((s: { id: string }) =>
          s.id === studentId
        ),
      );
      const rankings = await (await call("totem-rankings-v1")).json();
      ok(rankings.students.some((s: { id: string }) => s.id === studentId));
      deepStrictEqual(rankings, await (await call("totem-rankings-v1")).json());
      await sql`update students set status='ACTIVE' where id=${studentId}`;
      const payload = {
        event_id: events[0],
        class_id: classId,
        student_id: studentId,
        is_valid: true,
        detected_type: "pilha",
        waste_category_code: "BATTERY",
        category_source: "AI_CONFIRMED",
      };
      const created = await call("register-deposit-v1", payload);
      equal(created.status, 201);
      const snapshot = await created.json();
      const replay = await call("register-deposit-v1", payload);
      equal(replay.status, 200);
      deepStrictEqual(await replay.json(), snapshot);
      const divergent = await call("register-deposit-v1", {
        ...payload,
        detected_type: "cabo",
      });
      equal(divergent.status, 409);
      await divergent.body?.cancel();
      const anonymous = await call("register-deposit-v1", {
        ...payload,
        event_id: events[1],
        student_id: null,
      });
      equal(anonymous.status, 201);
      const anonymousSnapshot = await anonymous.json();
      equal(anonymousSnapshot.points_awarded_student, 0);
      const invalid = await call("register-deposit-v1", {
        ...payload,
        event_id: events[2],
        is_valid: false,
        detected_type: "objeto inválido",
        waste_category_code: null,
        category_source: null,
      });
      equal(invalid.status, 201);
      const invalidSnapshot = await invalid.json();
      equal(invalidSnapshot.points_awarded_student, 0);
      equal(invalidSnapshot.points_awarded_class, 0);
      const [afterStudent] =
        await sql`select points_student_balance from students where id=${studentId}`;
      const [afterClass] =
        await sql`select points_class_balance from classes where id=${classId}`;
      equal(
        afterStudent.points_student_balance -
          beforeStudent.points_student_balance,
        snapshot.points_awarded_student,
      );
      equal(
        afterClass.points_class_balance - beforeClass.points_class_balance,
        snapshot.points_awarded_class + anonymousSnapshot.points_awarded_class,
      );
      const [counts] =
        await sql`select count(*)::int as n from deposits where event_id in ${
          sql(events)
        }`;
      equal(counts.n, 3);
      const summary = await (await call("totem-student-summary-v1", {
        student_id: studentId,
      })).json();
      equal(
        summary.student.points_student_balance,
        afterStudent.points_student_balance,
      );
      ok(
        summary.stats.valid_deposits_count >= 1 &&
          summary.stats.invalid_deposits_count >= 1,
      );
      const recent = summary.recent_deposits.find((d: { event_id: string }) =>
        d.event_id === events[0]
      );
      equal(recent.points_awarded_student, snapshot.points_awarded_student);
      equal(recent.bonus_bincoins_awarded, snapshot.bonus_bincoins_awarded);
      const [totals] =
        await sql`select coalesce(sum(points_awarded_student) filter(where is_valid),0)::int as total from deposits where student_id=${studentId}`;
      equal(summary.stats.total_bins_generated, totals.total);
    } finally {
      // Keep the accepted local smoke events and their economic/history effects.
      // Restore only the temporary identity-state probes, never rewrite history.
      await sql`update students set status=${beforeState.status}, is_activated=${beforeState.is_activated} where id=${studentId}`;
      await sql`update machines set status=${beforeMachine.status} where id=${machineId}`;
      await sql.end();
    }
  },
});
