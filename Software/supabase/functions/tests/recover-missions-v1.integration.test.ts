import { deepStrictEqual, equal } from "node:assert/strict";
import postgres from "postgres";

import { createMissionRecoveryHandler } from "../recover-missions-v1/handler.ts";

const integrationEnabled =
  Deno.env.get("BINGO_EDGE_RECOVERY_INTEGRATION") === "1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const CLASS_ID = "20000000-0000-4000-8000-000000000001";

type TestDatabase = ReturnType<typeof postgres>;

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing integration test environment: ${name}`);
  }
  return value;
}

async function callRecovery(
  options: { apiKey?: string; authorization?: string } = {},
): Promise<Response> {
  const headers = new Headers();
  if (options.apiKey !== undefined) {
    headers.set("apikey", options.apiKey);
  }
  if (options.authorization !== undefined) {
    headers.set("Authorization", options.authorization);
  }
  return await createMissionRecoveryHandler()(
    new Request(
      "http://localhost/functions/v1/recover-missions-v1",
      {
        method: "POST",
        headers,
      },
    ),
  );
}

async function createDueInvalidDeposit(
  database: TestDatabase,
  eventId: string,
  minutesOverdue: number,
): Promise<void> {
  await database`
    select * from public.register_deposit_v1(
      ${eventId}::uuid,
      ${MACHINE_ID}::uuid,
      ${CLASS_ID}::uuid,
      false,
      null,
      'invalido',
      null,
      null
    )
  `;
  await database`
    select * from public.record_mission_processing_failure_v1(${eventId}::uuid)
  `;
  await database`
    update public.mission_processing_queue
    set enqueued_at = pg_catalog.clock_timestamp()
            - (${minutesOverdue}::integer * interval '1 minute'),
        next_attempt_at = pg_catalog.clock_timestamp()
            - (${minutesOverdue}::integer * interval '1 minute')
    where event_id = ${eventId}::uuid
  `;
}

async function createNeverAttemptedInvalidDeposit(
  database: TestDatabase,
  eventId: string,
): Promise<void> {
  await database`
    select * from public.register_deposit_v1(
      ${eventId}::uuid,
      ${MACHINE_ID}::uuid,
      ${CLASS_ID}::uuid,
      false,
      null,
      'invalido',
      null,
      null
    )
  `;
}

Deno.test({
  name:
    "recover-missions-v1 isolates failed events and keeps technical access private",
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const database = postgres(
      requireEnvironment("BINGO_EDGE_TEST_DATABASE_URL"),
      { max: 1, prepare: false },
    );
    const secretKey = requireEnvironment("SUPABASE_SECRET_KEY");
    const failedEventId = crypto.randomUUID();
    const successfulEventId = crypto.randomUUID();
    const neverAttemptedEventId = crypto.randomUUID();
    const triggerFunction = `test_fail_recovery_${
      crypto.randomUUID().replaceAll("-", "")
    }`;
    const triggerName = triggerFunction;

    try {
      for (
        const unauthorizedHeaders of [
          {},
          { apiKey: "sb_secret_wrong_test_value" },
          { authorization: `Bearer ${secretKey}` },
        ]
      ) {
        const unauthorized = await callRecovery(unauthorizedHeaders);
        equal(unauthorized.status, 401);
      }

      await createDueInvalidDeposit(database, failedEventId, 3);
      await createDueInvalidDeposit(database, successfulEventId, 2);
      await createNeverAttemptedInvalidDeposit(database, neverAttemptedEventId);
      await database.unsafe(`
        create function public.${triggerFunction}()
        returns trigger language plpgsql as $$
        begin
          raise exception using errcode = 'P0001', message = 'secret recovery failure';
        end;
        $$
      `);
      await database.unsafe(`
        create trigger ${triggerName}
        before update of processed_at on public.mission_processing_queue
        for each row
        when (new.event_id = '${failedEventId}'::uuid)
        execute function public.${triggerFunction}()
      `);

      const response = await callRecovery({ apiKey: secretKey });
      equal(response.status, 200);
      deepStrictEqual(await response.json(), {
        events_examined: 3,
        processed: 2,
        failed: 1,
        completions_created: 0,
        reward_applications_created: 0,
        batch_limit_reached: false,
      });

      const [failedState] = await database`
        select processed_at, attempt_count, last_error, next_attempt_at
        from public.mission_processing_queue
        where event_id = ${failedEventId}::uuid
      `;
      equal(failedState.processed_at, null);
      equal(failedState.attempt_count, 2);
      equal(failedState.last_error, "MISSION_PROCESSING_FAILED");
      equal(failedState.next_attempt_at instanceof Date, true);

      const [successfulState] = await database`
        select processed_at, attempt_count
        from public.mission_processing_queue
        where event_id = ${successfulEventId}::uuid
      `;
      equal(successfulState.processed_at instanceof Date, true);
      equal(successfulState.attempt_count, 1);

      const [neverAttemptedState] = await database`
        select processed_at, attempt_count, next_attempt_at
        from public.mission_processing_queue
        where event_id = ${neverAttemptedEventId}::uuid
      `;
      equal(neverAttemptedState.processed_at instanceof Date, true);
      equal(neverAttemptedState.attempt_count, 0);
      equal(neverAttemptedState.next_attempt_at, null);

      const repeated = await callRecovery({ apiKey: secretKey });
      equal(repeated.status, 200);
      equal(
        (await repeated.json() as { events_examined: number }).events_examined,
        0,
      );
    } finally {
      await database.unsafe(`
        drop trigger if exists ${triggerName}
        on public.mission_processing_queue
      `);
      await database.unsafe(
        `drop function if exists public.${triggerFunction}()`,
      );
      await database`
        delete from public.mission_processing_queue
        where event_id in (
          ${failedEventId}::uuid,
          ${successfulEventId}::uuid,
          ${neverAttemptedEventId}::uuid
        )
      `;
      await database`
        delete from public.deposits
        where event_id in (
          ${failedEventId}::uuid,
          ${successfulEventId}::uuid,
          ${neverAttemptedEventId}::uuid
        )
      `;
      await database`
        delete from public.audit_logs
        where metadata ->> 'event_id' in (
          ${failedEventId},
          ${successfulEventId},
          ${neverAttemptedEventId}
        )
      `;
      await database.end();
    }
  },
});
