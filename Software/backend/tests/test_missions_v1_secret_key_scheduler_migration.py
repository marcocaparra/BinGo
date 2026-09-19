import os
from pathlib import Path

import psycopg
import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RPC_TEST_DATABASE_URL = os.getenv("BINGO_RPC_TEST_DATABASE_URL")
DATABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "database"
    / "migrations"
    / "018_missions_v1_secret_key_scheduler.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260918130000_missions_v1_secret_key_scheduler.sql"
)


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_migration_updates_only_the_existing_scheduler_authentication():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "cron.alter_job(" in sql
    assert "cron.schedule(" not in sql
    assert "cron.unschedule(" not in sql
    assert "bingo-missions-v1-recovery-every-minute" in sql
    assert "'* * * * *'" in sql
    assert "'/functions/v1/recover-missions-v1'" in sql
    assert "bingo_missions_project_url" in sql
    assert "bingo_missions_recovery_secret_key" in sql
    assert "'apikey', secrets.secret_key" in sql
    assert "'authorization'" not in sql
    assert "bingo_missions_recovery_service_role_key" not in sql
    assert "sb_secret_" not in sql
    assert "active :=" not in sql


def test_migration_preserves_an_inactive_scheduler():
    if not RPC_TEST_DATABASE_URL:
        pytest.skip("BINGO_RPC_TEST_DATABASE_URL is not configured")

    with psycopg.connect(RPC_TEST_DATABASE_URL, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                select jobid, active
                from cron.job
                where jobname = 'bingo-missions-v1-recovery-every-minute'
                """
            )
            job_id, original_active = cursor.fetchone()
            try:
                cursor.execute(
                    "select cron.alter_job(job_id := %s, active := false)",
                    (job_id,),
                )
                cursor.execute(executable_body(DATABASE_MIGRATION))
                cursor.execute(
                    "select active from cron.job where jobid = %s", (job_id,)
                )
                assert cursor.fetchone()[0] is False
            finally:
                cursor.execute(
                    "select cron.alter_job(job_id := %s, active := %s)",
                    (job_id, original_active),
                )
