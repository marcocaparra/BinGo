"""Provas locais de equivalencia, rollback legado e preservacao de historico."""
import os
import uuid
from pathlib import Path

import psycopg
import pytest

ROOT = Path(__file__).resolve().parents[2]
DATABASE = ROOT / 'database/migrations/023_admin_auth_foundation.sql'
SUPABASE = ROOT / 'supabase/migrations/20260930120000_admin_auth_foundation.sql'
URL = os.getenv('BINGO_TEST_DATABASE_URL', 'postgresql://postgres:postgres@127.0.0.1:54322/postgres')


def test_migration_tracks_are_identical():
    assert DATABASE.read_text(encoding='utf-8') == SUPABASE.read_text(encoding='utf-8')


def prior_schema(connection):
    # Reconstroi pre-023 somente nesta transacao revertida ao final.
    connection.execute('drop function public.get_my_admin_context_v1()')
    connection.execute('''alter table public.admins
        drop constraint admins_role_school_check,
        drop constraint admins_role_check,
        drop constraint admins_status_check,
        drop column status, drop column auth_user_id,
        alter column school_id set not null,
        add constraint admins_role_check check
            (role in ('ADMIN','ADMIN_CONQUISTA','BINGO_ADMIN','ADMIN_A','ADMIN_B','ADMIN_C'))''')


def migration_body():
    # O runner de teste ja controla a transacao; preserva todo o corpo executavel.
    sql = DATABASE.read_text(encoding='utf-8')
    return sql[sql.index('begin;') + len('begin;'):sql.rindex('commit;')]


@pytest.fixture
def connection():
    try:
        db = psycopg.connect(URL)
    except psycopg.OperationalError:
        pytest.skip('Supabase local indisponivel')
    try:
        yield db
    finally:
        db.rollback()
        db.close()


@pytest.mark.parametrize('legacy', ['ADMIN', 'ADMIN_CONQUISTA', 'BINGO_ADMIN'])
def test_ambiguous_legacy_records_abort_before_ddl(connection, legacy):
    prior_schema(connection)
    school = connection.execute('select id from public.schools limit 1').fetchone()[0]
    admin_id = uuid.uuid4()
    connection.execute('insert into public.admins(id,school_id,name,email,role) values(%s,%s,%s,%s,%s)',
                       (admin_id, school, 'Legado', f'{admin_id}@example.test', legacy))
    with pytest.raises(psycopg.errors.RaiseException, match='Classifique manualmente'):
        with connection.transaction():
            connection.execute(migration_body())
    assert connection.execute('select role from public.admins where id=%s', (admin_id,)).fetchone() == (legacy,)
    assert connection.execute("select count(*) from information_schema.columns where table_schema='public' and table_name='admins' and column_name='auth_user_id'").fetchone() == (0,)
    assert connection.execute("select to_regprocedure('public.get_my_admin_context_v1()')").fetchone() == (None,)


def test_incremental_migration_preserves_admin_delivery_and_audit(connection):
    prior_schema(connection)
    school, student, reward = connection.execute('''select s.school_id,s.id,r.id
        from public.students s join public.rewards r on r.school_id=s.school_id limit 1''').fetchone()
    admin_id, redemption_id, audit_id = [uuid.uuid4() for _ in range(3)]
    # Classificacao manual explicita desta fixture de escola, nao conversao de papel legado.
    connection.execute("insert into public.admins(id,school_id,name,email,role,password_hash) values(%s,%s,'Manual B',%s,'ADMIN_B','legacy-hash')", (admin_id, school, f'{admin_id}@example.test'))
    connection.execute("insert into public.redemptions(id,school_id,student_id,reward_id,code,status,delivered_by_admin_id) values(%s,%s,%s,%s,%s,'DELIVERED',%s)", (redemption_id, school, student, reward, str(redemption_id), admin_id))
    connection.execute("insert into public.audit_logs(id,school_id,actor_type,actor_id,action,metadata) values(%s,%s,'ADMIN',%s,'HISTORICAL','{\"preserved\": true}')", (audit_id, school, admin_id))
    before_admin = connection.execute('select * from public.admins where id=%s', (admin_id,)).fetchone()
    before_redemption = connection.execute('select * from public.redemptions where id=%s', (redemption_id,)).fetchone()
    before_audit = connection.execute('select * from public.audit_logs where id=%s', (audit_id,)).fetchone()
    connection.execute(migration_body())
    assert connection.execute('select id,school_id,name,email,role,created_at,updated_at,password_hash from public.admins where id=%s', (admin_id,)).fetchone() == before_admin
    assert connection.execute('select * from public.redemptions where id=%s', (redemption_id,)).fetchone() == before_redemption
    assert connection.execute('select * from public.audit_logs where id=%s', (audit_id,)).fetchone() == before_audit
    assert connection.execute('select auth_user_id,status from public.admins where id=%s', (admin_id,)).fetchone() == (None, 'ACTIVE')
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        with connection.transaction():
            connection.execute('delete from public.admins where id=%s', (admin_id,))
