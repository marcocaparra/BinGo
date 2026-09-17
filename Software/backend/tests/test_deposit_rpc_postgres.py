import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import psycopg
import pytest


RPC_TEST_DATABASE_URL = os.getenv("BINGO_RPC_TEST_DATABASE_URL")


@pytest.mark.skipif(
    not RPC_TEST_DATABASE_URL,
    reason="Defina BINGO_RPC_TEST_DATABASE_URL para executar a prova concorrente da RPC em PostgreSQL.",
)
def test_register_deposit_v1_is_concurrency_safe():
    school_id = uuid.uuid4()
    class_id = uuid.uuid4()
    student_id = uuid.uuid4()
    machine_id = uuid.uuid4()
    event_id = uuid.uuid4()

    with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute("insert into public.schools (id, name) values (%s, 'Escola concorrencia')", (school_id,))
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

    barrier = threading.Barrier(2)

    def call_rpc():
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            barrier.wait()
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    select * from public.register_deposit_v1(
                        %s, %s, %s, true, %s, 'mouse', 'PERIPHERAL', 'AI_CONFIRMED'
                    )
                    """,
                    (event_id, machine_id, class_id, student_id),
                )
                return cursor.fetchone()

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: call_rpc(), range(2)))

        assert results[0][0] == results[1][0]
        assert {results[0][-1], results[1][-1]} == {False, True}

        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute("select count(*) from public.deposits where event_id = %s", (event_id,))
                assert cursor.fetchone()[0] == 1
                cursor.execute("select count(*) from public.mission_processing_queue where event_id = %s", (event_id,))
                assert cursor.fetchone()[0] == 1
                cursor.execute("select points_student_balance from public.students where id = %s", (student_id,))
                assert cursor.fetchone()[0] == 800
                cursor.execute("select points_class_balance from public.classes where id = %s", (class_id,))
                assert cursor.fetchone()[0] == 1900
    finally:
        with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
            with connection.cursor() as cursor:
                cursor.execute("delete from public.mission_processing_queue where event_id = %s", (event_id,))
                cursor.execute("delete from public.deposits where event_id = %s", (event_id,))
                cursor.execute("delete from public.audit_logs where actor_id = %s", (machine_id,))
                cursor.execute("delete from public.students where id = %s", (student_id,))
                cursor.execute("delete from public.classes where id = %s", (class_id,))
                cursor.execute("delete from public.machines where id = %s", (machine_id,))
                cursor.execute("delete from public.school_settings where school_id = %s", (school_id,))
                cursor.execute("delete from public.schools where id = %s", (school_id,))
