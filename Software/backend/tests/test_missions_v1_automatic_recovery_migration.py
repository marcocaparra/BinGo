from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "database"
    / "migrations"
    / "017_missions_v1_automatic_recovery.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260918120000_missions_v1_automatic_recovery.sql"
)


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_never_attempted_events_are_due_without_changing_economic_logic():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "queue.processed_at is null" in sql
    assert "queue.next_attempt_at is null" in sql
    assert "queue.next_attempt_at <= pg_catalog.clock_timestamp()" in sql
    assert "order by queue.next_attempt_at, queue.enqueued_at, queue.event_id" in sql
    assert "for update skip locked" in sql
    assert "public.process_mission_event_v1(v_event_id)" in sql
    assert "public.record_mission_processing_failure_v1(v_event_id)" in sql


def test_scheduler_calls_only_the_existing_recovery_edge_function_each_minute():
    sql = executable_body(DATABASE_MIGRATION).lower()
    scheduler = sql[sql.index("select cron.schedule(") :]
    assert "'bingo-missions-v1-recovery-every-minute'" in scheduler
    assert "'* * * * *'" in scheduler
    assert "net.http_post(" in scheduler
    assert "'/functions/v1/recover-missions-v1'" in scheduler
    assert "from vault.decrypted_secrets" in scheduler
    assert "bingo_missions_project_url" in scheduler
    assert "bingo_missions_recovery_service_role_key" in scheduler
    assert "process_mission_event_v1" not in scheduler
    assert "mission_completions" not in scheduler
    assert "mission_reward_applications" not in scheduler


def test_scheduler_contains_no_versioned_credential():
    sql = executable_body(DATABASE_MIGRATION)
    assert "sb_secret_" not in sql
    assert "eyJhbGci" not in sql
    assert "SUPABASE_SERVICE_ROLE_KEY=" not in sql
