import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = REPOSITORY_ROOT / "database" / "migrations" / "014_missions_v1_processing.sql"
SUPABASE_MIGRATION = REPOSITORY_ROOT / "supabase" / "migrations" / "20260917120000_missions_v1_processing.sql"
RPC_TEST_DATABASE_URL = os.getenv("BINGO_RPC_TEST_DATABASE_URL")


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_queue_is_minimal_and_register_deposit_enqueues_atomically():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "create table public.mission_processing_queue" in sql
    assert "event_id uuid primary key" in sql
    assert "references public.deposits(event_id) on delete restrict" in sql
    assert "insert into public.mission_processing_queue" in sql
    assert "on conflict on constraint mission_processing_queue_pkey do nothing" in sql

    queue_definition = sql.split("create table public.mission_processing_queue", 1)[1].split(");", 1)[0]
    for duplicated_authority in (
        "student_id",
        "class_id",
        "progress",
        "target",
        "reward_bincoins",
        "reward_xp",
    ):
        assert duplicated_authority not in queue_definition


def test_processor_is_server_side_atomic_and_minimally_granted():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "create function public.process_mission_event_v1(p_event_id uuid)" in sql
    assert "security definer" in sql
    assert "set search_path = ''" in sql
    assert "for update skip locked" in sql
    assert "public.calculate_mission_progress_v1" in sql
    assert "deposit.created_at" in sql
    assert "mission_completions" in sql
    assert "mission_reward_applications" in sql
    assert "mission_completed_v1" in sql
    assert "processed_at = pg_catalog.clock_timestamp()" in sql
    assert "grant execute on function public.process_mission_event_v1(uuid)" in sql
    assert "to service_role" in sql
    assert "grant execute on function public.process_mission_event_v1(uuid)\nto authenticated" not in sql
    assert "grant execute on function public.process_mission_event_v1(uuid)\nto anon" not in sql


@pytest.mark.skipif(
    not RPC_TEST_DATABASE_URL,
    reason="Defina BINGO_RPC_TEST_DATABASE_URL para executar a prova concorrente do processador.",
)
def test_process_mission_event_v1_is_concurrency_safe():
    school_id = uuid.uuid4()
    class_id = uuid.uuid4()
    student_id = uuid.uuid4()
    machine_id = uuid.uuid4()
    definition_id = uuid.uuid4()
    cycle_id = uuid.uuid4()
    event_id = uuid.uuid4()

    with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute("insert into public.schools (id, name) values (%s, 'Escola concorrencia Missoes')", (school_id,))
            cursor.execute("insert into public.school_settings (school_id) values (%s)", (school_id,))
            cursor.execute(
                "insert into public.classes (id, school_id, segment, grade, name) values (%s, %s, 'TESTE', '1', 'Turma')",
                (class_id, school_id),
            )
            cursor.execute(
                "insert into public.students (id, school_id, class_id, name, status) values (%s, %s, %s, 'Aluno', 'ACTIVE')",
                (student_id, school_id, class_id),
            )
            cursor.execute(
                "insert into public.machines (id, school_id, name, status) values (%s, %s, 'Totem', 'ONLINE')",
                (machine_id, school_id),
            )
            cursor.execute(
                """
                insert into public.mission_definitions (
                    id, code, title, scope, metric, recurrence, target,
                    reward_bincoins, reward_xp
                ) values (%s, %s, 'Concorrencia', 'STUDENT',
                          'VALID_DEPOSIT_COUNT', 'MONTHLY', 1, 100, 200)
                """,
                (definition_id, f"CONCURRENCY_{definition_id.hex}"),
            )
            cursor.execute(
                """
                insert into public.mission_cycles (
                    id, definition_id, school_id, starts_at, ends_at,
                    timezone, scope, metric, recurrence, target,
                    reward_bincoins, reward_xp
                ) values (
                    %s, %s, %s,
                    date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo',
                    (date_trunc('month', now() at time zone 'America/Sao_Paulo') + interval '1 month') at time zone 'America/Sao_Paulo',
                    'America/Sao_Paulo', 'STUDENT', 'VALID_DEPOSIT_COUNT',
                    'MONTHLY', 1, 100, 200
                )
                """,
                (cycle_id, definition_id, school_id),
            )
            cursor.execute(
                """
                select * from public.register_deposit_v1(
                    %s, %s, %s, true, %s, 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
                )
                """,
                (event_id, machine_id, class_id, student_id),
            )

    barrier = threading.Barrier(2)

    def process_event():
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            barrier.wait()
            with connection.cursor() as cursor:
                cursor.execute(
                    "select * from public.process_mission_event_v1(%s)",
                    (event_id,),
                )
                return cursor.fetchone()

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: process_event(), range(2)))

        assert sum(1 for result in results if result[0]) == 1

        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "select count(*) from public.mission_completions where cycle_id = %s and student_id = %s",
                    (cycle_id, student_id),
                )
                assert cursor.fetchone()[0] == 1
                cursor.execute(
                    """
                    select count(*)
                    from public.mission_reward_applications as application
                    join public.mission_completions as completion
                      on completion.id = application.completion_id
                    where completion.cycle_id = %s
                    """,
                    (cycle_id,),
                )
                assert cursor.fetchone()[0] == 2
                cursor.execute(
                    "select processed_at is not null from public.mission_processing_queue where event_id = %s",
                    (event_id,),
                )
                assert cursor.fetchone()[0] is True
                cursor.execute(
                    "select count(*) from public.audit_logs where action = 'MISSION_COMPLETED_V1' and metadata ->> 'event_id' = %s",
                    (str(event_id),),
                )
                assert cursor.fetchone()[0] == 1
                cursor.execute("select points_student_balance from public.students where id = %s", (student_id,))
                assert cursor.fetchone()[0] == 900
                cursor.execute("select points_class_balance from public.classes where id = %s", (class_id,))
                assert cursor.fetchone()[0] == 2100
    finally:
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute("delete from public.audit_logs where metadata ->> 'event_id' = %s", (str(event_id),))
                cursor.execute(
                    """
                    delete from public.mission_reward_applications
                    where completion_id in (
                        select id from public.mission_completions where cycle_id = %s
                    )
                    """,
                    (cycle_id,),
                )
                cursor.execute("delete from public.mission_completions where cycle_id = %s", (cycle_id,))
                cursor.execute("delete from public.mission_processing_queue where event_id = %s", (event_id,))
                cursor.execute("delete from public.deposits where event_id = %s", (event_id,))
                cursor.execute("delete from public.mission_cycles where id = %s", (cycle_id,))
                cursor.execute("delete from public.mission_definitions where id = %s", (definition_id,))
                cursor.execute("delete from public.students where id = %s", (student_id,))
                cursor.execute("delete from public.classes where id = %s", (class_id,))
                cursor.execute("delete from public.machines where id = %s", (machine_id,))
                cursor.execute("delete from public.school_settings where school_id = %s", (school_id,))
                cursor.execute("delete from public.schools where id = %s", (school_id,))
