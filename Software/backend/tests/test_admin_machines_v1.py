from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[2]


def test_machine_read_migrations_are_identical():
    # O checkout Windows pode usar CRLF em um trilho e LF no outro.
    # Compare todo o SQL, normalizando apenas as quebras de linha do arquivo.
    assert (ROOT / 'database/migrations/030_admin_machines_v1.sql').read_text(encoding='utf-8') == (
        ROOT / 'supabase/migrations/20261001150000_admin_machines_v1.sql'
    ).read_text(encoding='utf-8')


def test_machine_read_does_not_widen_technical_or_browser_grants():
    with psycopg.connect('postgresql://postgres:postgres@127.0.0.1:54322/postgres') as db:
        assert db.execute("select has_function_privilege('authenticated', 'public.get_admin_machines_v1()', 'execute'), has_function_privilege('service_role', 'public.get_admin_machines_v1()', 'execute'), has_any_column_privilege('authenticated', 'public.machines', 'select'), has_column_privilege('service_role', 'public.machines', 'api_key_hash', 'select')").fetchone() == (True, False, False, True)
