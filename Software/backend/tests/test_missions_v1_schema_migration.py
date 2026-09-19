from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT / "database" / "migrations" / "012_missions_v1_schema.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260915120000_missions_v1_schema.sql"
)


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("begin;") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_migration_is_structural_only():
    sql = executable_body(DATABASE_MIGRATION).lower()

    assert "create function" not in sql
    assert "create or replace function" not in sql
    assert "create policy" not in sql
    assert "alter table public.deposits" not in sql
    assert "update public." not in sql
    assert "insert into public." not in sql
    assert "idx_deposits_class_created_at_valid" in sql


def test_migration_defines_only_the_four_approved_mission_tables():
    sql = executable_body(DATABASE_MIGRATION).lower()
    expected = {
        "mission_definitions",
        "mission_cycles",
        "mission_completions",
        "mission_reward_applications",
    }

    for table in expected:
        assert f"create table public.{table}" in sql

    forbidden = {
        "mission_progress",
        "mission_participants",
        "mission_enrollments",
        "mission_definition_rewards",
        "mission_cycle_rewards",
        "student_missions",
        "class_missions",
    }
    for table in forbidden:
        assert f"create table public.{table}" not in sql
