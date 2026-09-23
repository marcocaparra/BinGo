from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DATABASE_MIGRATION = (
    REPOSITORY_ROOT / "database" / "migrations" / "013_get_active_missions_v1.sql"
)
SUPABASE_MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260915130000_get_active_missions_v1.sql"
)


def executable_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8")
    return sql[sql.index("create function") :]


def test_database_and_supabase_migrations_have_the_same_executable_body():
    assert executable_body(DATABASE_MIGRATION) == executable_body(SUPABASE_MIGRATION)


def test_rpc_is_authenticated_read_only_and_has_minimal_grants():
    sql = executable_body(DATABASE_MIGRATION).lower()

    assert "create function public.get_active_missions_v1()" in sql
    assert "security definer" in sql
    assert "set search_path = ''" in sql
    assert "auth.uid()" in sql
    assert "student.status = 'active'" in sql
    assert "is_activated" not in sql
    assert "revoke all on function public.get_active_missions_v1()" in sql
    assert "from public, anon, authenticated, service_role" in sql
    assert "grant execute on function public.get_active_missions_v1()" in sql
    assert "to authenticated" in sql

    for forbidden in (
        "insert into",
        "update public.",
        "delete from",
        "create table",
        "create policy",
        "alter table",
    ):
        assert forbidden not in sql


def test_rpc_contract_uses_historical_deposits_and_active_cycle_boundaries():
    sql = executable_body(DATABASE_MIGRATION).lower()

    for returned_column in (
        "cycle_id uuid",
        "definition_id uuid",
        "definition_code text",
        "definition_title text",
        "scope text",
        "metric text",
        "starts_at timestamptz",
        "ends_at timestamptz",
        "target bigint",
        "reward_bincoins integer",
        "reward_xp integer",
        "progress bigint",
        "is_achieved boolean",
        "achieved_at timestamptz",
        "is_completed boolean",
        "materialized_at timestamptz",
    ):
        assert returned_column in sql

    assert "cycle.starts_at <= pg_catalog.now()" in sql
    assert "pg_catalog.now() < cycle.ends_at" in sql
    assert "deposit.created_at >= cycle.starts_at" in sql
    assert "deposit.created_at < cycle.ends_at" in sql
    assert "order by deposit.created_at, deposit.id" in sql
    assert "deposit.points_awarded_class::bigint" in sql
    assert "classes.points_class_balance" not in sql
    assert "order by cycle.starts_at, cycle.code, cycle.id" in sql
