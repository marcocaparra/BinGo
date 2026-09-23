import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest


DATABASE_URL = os.getenv(
    "BINGO_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
)
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT / "database" / "migrations" / "022_binbazar_statement_v1.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260923120000_binbazar_statement_v1.sql"
)


def test_database_and_supabase_migrations_have_the_same_executable_body():
    database_sql = DATABASE_MIGRATION.read_text(encoding="utf-8")
    supabase_sql = SUPABASE_MIGRATION.read_text(encoding="utf-8")
    assert database_sql[database_sql.index("begin;") :] == supabase_sql[
        supabase_sql.index("begin;") :
    ]


def test_concurrent_redemptions_serialize_stock_and_balance():
    try:
        connection = psycopg.connect(DATABASE_URL, autocommit=True)
    except psycopg.OperationalError:
        pytest.skip("Supabase local nao esta disponivel")

    fixture = _seed_fixture(connection)
    try:
        stock_barrier = threading.Barrier(2)
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(
                    _request,
                    fixture["auth_ids"][index],
                    uuid.uuid4(),
                    fixture["finite_reward_id"],
                    stock_barrier,
                )
                for index in range(2)
            ]
            stock_results = [future.result(timeout=15) for future in futures]

        assert sorted(result[0] for result in stock_results) == ["23514", "ok"]
        row = connection.execute(
            """
            select stock_qty,
                   (select count(*) from public.redemptions where reward_id = %s),
                   (select sum(points_student_balance) from public.students where id = any(%s))
            from public.rewards where id = %s
            """,
            (
                fixture["finite_reward_id"],
                fixture["student_ids"],
                fixture["finite_reward_id"],
            ),
        ).fetchone()
        assert row == (0, 1, 1600)

        connection.execute(
            "update public.students set points_student_balance = 500 where id = %s",
            (fixture["student_ids"][0],),
        )
        balance_barrier = threading.Barrier(2)
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(
                    _request,
                    fixture["auth_ids"][0],
                    uuid.uuid4(),
                    reward_id,
                    balance_barrier,
                )
                for reward_id in fixture["balance_reward_ids"]
            ]
            balance_results = [future.result(timeout=15) for future in futures]

        assert sorted(result[0] for result in balance_results) == ["23514", "ok"]
        assert (
            connection.execute(
                "select points_student_balance from public.students where id = %s",
                (fixture["student_ids"][0],),
            ).fetchone()[0]
            == 100
        )
        assert (
            connection.execute(
                "select count(*) from public.redemptions where reward_id = any(%s)",
                (fixture["balance_reward_ids"],),
            ).fetchone()[0]
            == 1
        )
    finally:
        _cleanup(connection, fixture)
        connection.close()


def _request(auth_id, request_id, reward_id, barrier):
    barrier.wait(timeout=10)
    try:
        with psycopg.connect(DATABASE_URL) as connection:
            connection.execute(
                "select set_config('request.jwt.claim.sub', %s, false)",
                (str(auth_id),),
            )
            connection.execute("set role authenticated")
            row = connection.execute(
                "select redemption_id from public.request_redemption_v1(%s, %s)",
                (request_id, reward_id),
            ).fetchone()
            return "ok", row[0]
    except psycopg.Error as error:
        return error.sqlstate, None


def _seed_fixture(connection):
    school_id = uuid.uuid4()
    class_id = uuid.uuid4()
    student_ids = [uuid.uuid4(), uuid.uuid4()]
    auth_ids = [uuid.uuid4(), uuid.uuid4()]
    finite_reward_id = uuid.uuid4()
    balance_reward_ids = [uuid.uuid4(), uuid.uuid4()]

    connection.execute(
        "insert into public.schools (id, name) values (%s, 'Concorrencia Bazaar')",
        (school_id,),
    )
    connection.execute(
        """
        insert into public.classes (id, school_id, segment, grade, name)
        values (%s, %s, 'TEST', '1', 'Turma concorrencia')
        """,
        (class_id, school_id),
    )
    for index in range(2):
        connection.execute(
            """
            insert into public.students (
                id, school_id, class_id, name, points_student_balance,
                status, auth_user_id
            ) values (%s, %s, %s, %s, 1000, 'ACTIVE', %s)
            """,
            (
                student_ids[index],
                school_id,
                class_id,
                f"Aluno concorrencia {index}",
                auth_ids[index],
            ),
        )
    connection.execute(
        """
        insert into public.rewards (
            id, school_id, name, cost_points, is_active, status, stock_qty
        ) values (%s, %s, 'Ultima unidade', 400, true, 'AVAILABLE', 1)
        """,
        (finite_reward_id, school_id),
    )
    for index, reward_id in enumerate(balance_reward_ids):
        connection.execute(
            """
            insert into public.rewards (
                id, school_id, name, cost_points, is_active, status, stock_qty
            ) values (%s, %s, %s, 400, true, 'AVAILABLE', null)
            """,
            (reward_id, school_id, f"Saldo concorrente {index}"),
        )
    return {
        "school_id": school_id,
        "class_id": class_id,
        "student_ids": student_ids,
        "auth_ids": auth_ids,
        "finite_reward_id": finite_reward_id,
        "balance_reward_ids": balance_reward_ids,
    }


def _cleanup(connection, fixture):
    connection.execute(
        "delete from public.audit_logs where school_id = %s",
        (fixture["school_id"],),
    )
    connection.execute(
        "delete from public.redemptions where school_id = %s",
        (fixture["school_id"],),
    )
    connection.execute(
        "delete from public.rewards where school_id = %s",
        (fixture["school_id"],),
    )
    connection.execute(
        "delete from public.students where school_id = %s",
        (fixture["school_id"],),
    )
    connection.execute(
        "delete from public.classes where school_id = %s",
        (fixture["school_id"],),
    )
    connection.execute(
        "delete from public.schools where id = %s",
        (fixture["school_id"],),
    )
