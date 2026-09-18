from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT / "database" / "migrations" / "015_missions_v1_immediate_retry.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260917130000_missions_v1_immediate_retry.sql"
)


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_retry_state_is_minimal_sanitized_and_indexed():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "add column attempt_count integer not null default 0" in sql
    assert "add column last_error text" in sql
    assert "add column next_attempt_at timestamptz" in sql
    assert "last_error = 'mission_processing_failed'" in sql
    assert "idx_mission_processing_queue_retry_due" in sql
    assert "where processed_at is null" in sql
    assert "p_error" not in sql
    assert "p_message" not in sql


def test_public_processor_respects_backoff_and_failure_writer_is_server_only():
    sql = executable_body(DATABASE_MIGRATION).lower()
    assert "rename to process_mission_event_v1_core" in sql
    assert "v_next_attempt_at > pg_catalog.clock_timestamp()" in sql
    assert "public.process_mission_event_v1_core(p_event_id)" in sql
    assert "create function public.record_mission_processing_failure_v1(p_event_id uuid)" in sql
    assert "when v_attempt_count = 1 then interval '1 minute'" in sql
    assert "when v_attempt_count = 2 then interval '5 minutes'" in sql
    assert "when v_attempt_count = 3 then interval '15 minutes'" in sql
    assert "else interval '1 hour'" in sql
    assert "grant execute on function public.record_mission_processing_failure_v1(uuid)" in sql
    assert "to service_role" in sql
    assert "to authenticated" not in sql
    assert "to anon" not in sql
