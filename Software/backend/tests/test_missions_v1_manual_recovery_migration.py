import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT / "database" / "migrations" / "016_missions_v1_manual_recovery.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260917140000_missions_v1_manual_recovery.sql"
)
RPC_TEST_DATABASE_URL = os.getenv("BINGO_RPC_TEST_DATABASE_URL")


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_recovery_selects_one_due_event_and_reuses_existing_operations():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "create function public.recover_next_mission_event_v1()" in sql
    assert "queue.processed_at is null" in sql
    assert "queue.next_attempt_at <= pg_catalog.clock_timestamp()" in sql
    assert "for update skip locked" in sql
    assert "limit 1" in sql
    assert "public.process_mission_event_v1(v_event_id)" in sql
    assert "public.record_mission_processing_failure_v1(v_event_id)" in sql
    assert "grant execute on function public.recover_next_mission_event_v1()" in sql
    assert "to service_role" in sql
    assert "to authenticated" not in sql
    assert "to anon" not in sql


@pytest.mark.skipif(
    not RPC_TEST_DATABASE_URL,
    reason="Defina BINGO_RPC_TEST_DATABASE_URL para executar a prova concorrente do recuperador.",
)
def test_two_recoverers_skip_the_same_locked_event():
    school_id = uuid.uuid4()
    class_id = uuid.uuid4()
    machine_id = uuid.uuid4()
    event_id = uuid.uuid4()
    suffix = uuid.uuid4().hex
    trigger_function = f"test_delay_mission_recovery_{suffix}"
    trigger_name = f"test_delay_mission_recovery_{suffix}"

    with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "insert into public.schools (id, name) values (%s, 'Escola concorrencia recuperador')",
                (school_id,),
            )
            cursor.execute("insert into public.school_settings (school_id) values (%s)", (school_id,))
            cursor.execute(
                "insert into public.classes (id, school_id, segment, grade, name) values (%s, %s, 'TESTE', '1', 'Turma')",
                (class_id, school_id),
            )
            cursor.execute(
                "insert into public.machines (id, school_id, name, status) values (%s, %s, 'Totem', 'ONLINE')",
                (machine_id, school_id),
            )
            cursor.execute(
                "select * from public.register_deposit_v1(%s, %s, %s, false, null, 'invalido', null, null)",
                (event_id, machine_id, class_id),
            )
            cursor.execute(
                "select * from public.record_mission_processing_failure_v1(%s)",
                (event_id,),
            )
            cursor.execute(
                "update public.mission_processing_queue set enqueued_at = clock_timestamp() - interval '1 minute', next_attempt_at = clock_timestamp() - interval '1 minute' where event_id = %s",
                (event_id,),
            )
            cursor.execute(
                f"""
                create function public.{trigger_function}()
                returns trigger language plpgsql as $$
                begin
                    perform pg_catalog.pg_sleep(0.5);
                    return new;
                end;
                $$
                """
            )
            cursor.execute(
                f"""
                create trigger {trigger_name}
                before update of processed_at on public.mission_processing_queue
                for each row
                when (new.event_id = '{event_id}'::uuid)
                execute function public.{trigger_function}()
                """
            )

    barrier = threading.Barrier(2)

    def recover_one():
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            barrier.wait()
            with connection.cursor() as cursor:
                cursor.execute("select * from public.recover_next_mission_event_v1()")
                return cursor.fetchone()

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: recover_one(), range(2)))

        assert sum(result is not None for result in results) == 1
        recovered = next(result for result in results if result is not None)
        assert recovered[0] == event_id
        assert recovered[1] == "PROCESSED"

        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "select processed_at is not null, attempt_count from public.mission_processing_queue where event_id = %s",
                    (event_id,),
                )
                assert cursor.fetchone() == (True, 1)
    finally:
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    f"drop trigger if exists {trigger_name} on public.mission_processing_queue"
                )
                cursor.execute(f"drop function if exists public.{trigger_function}()")
                cursor.execute("delete from public.mission_processing_queue where event_id = %s", (event_id,))
                cursor.execute("delete from public.deposits where event_id = %s", (event_id,))
                cursor.execute("delete from public.audit_logs where actor_id = %s", (machine_id,))
                cursor.execute("delete from public.classes where id = %s", (class_id,))
                cursor.execute("delete from public.machines where id = %s", (machine_id,))
                cursor.execute("delete from public.school_settings where school_id = %s", (school_id,))
                cursor.execute("delete from public.schools where id = %s", (school_id,))
