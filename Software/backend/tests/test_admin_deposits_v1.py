from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[2]


def test_admin_deposit_read_migrations_are_identical():
    assert (ROOT / 'database/migrations/031_admin_deposits_v1.sql').read_text(
        encoding='utf-8'
    ) == (ROOT / 'supabase/migrations/20261001160000_admin_deposits_v1.sql').read_text(
        encoding='utf-8'
    )


def test_admin_deposit_read_preserves_rls_and_direct_grants():
    with psycopg.connect('postgresql://postgres:postgres@127.0.0.1:54322/postgres') as db:
        assert db.execute(
            """
            select
              has_function_privilege('authenticated', 'public.get_admin_deposits_v1()', 'execute'),
              has_function_privilege('service_role', 'public.get_admin_deposits_v1()', 'execute'),
              has_column_privilege('authenticated', 'public.deposits', 'school_id', 'select'),
              (select count(*) from pg_policies where schemaname='public' and tablename='deposits')
            """
        ).fetchone() == (True, False, False, 1)
