"""Integridade incremental e corrida real de matricula, exclusivamente em PostgreSQL local."""
import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest

ROOT = Path(__file__).resolve().parents[2]
DATABASE = ROOT / 'database/migrations/024_admin_school_management_foundation.sql'
SUPABASE = ROOT / 'supabase/migrations/20260930130000_admin_school_management_foundation.sql'
URL = os.getenv('BINGO_RPC_TEST_DATABASE_URL')


def test_school_migration_tracks_are_identical():
    assert DATABASE.read_text(encoding='utf-8') == SUPABASE.read_text(encoding='utf-8')


@pytest.mark.skipif(not URL, reason='Defina BINGO_RPC_TEST_DATABASE_URL para prova local PostgreSQL.')
def test_incremental_school_migration_preserves_historical_students_and_classes():
    with psycopg.connect(URL) as db:
        try:
            signatures = db.execute("""select oid::regprocedure::text from pg_proc where
                pronamespace='public'::regnamespace and proname in
                ('require_school_admin_v1','get_admin_students_v1','get_admin_classes_v1',
                'create_admin_student_v1','update_admin_student_v1','create_admin_class_v1','update_admin_class_v1')""").fetchall()
            for signature, in signatures:
                db.execute('drop function ' + signature)
            db.execute('alter table public.students drop column registration, drop column email')
            students = db.execute('select * from public.students order by id').fetchall()
            classes = db.execute('select * from public.classes order by id').fetchall()
            sql = DATABASE.read_text(encoding='utf-8')
            db.execute(sql[sql.index('begin;') + 6:sql.rindex('commit;')])
            assert [r[:-2] for r in db.execute('select * from public.students order by id')] == students
            assert all(r[-2:] == (None, None) for r in db.execute('select * from public.students'))
            assert db.execute('select * from public.classes order by id').fetchall() == classes
        finally:
            db.rollback()


@pytest.mark.skipif(not URL, reason='Defina BINGO_RPC_TEST_DATABASE_URL para prova concorrente local.')
@pytest.mark.parametrize('updating', [False, True], ids=['create-race', 'update-race'])
def test_registration_race_has_one_winner_and_one_audit(updating):
    school, classroom, admin, auth = [uuid.uuid4() for _ in range(4)]
    student_ids = [uuid.uuid4(), uuid.uuid4()]
    barrier = threading.Barrier(2)
    with psycopg.connect(URL, autocommit=True) as db:
        db.execute("insert into public.schools(id,name) values(%s,'Race school')", (school,))
        db.execute("insert into public.classes(id,school_id,segment,grade,name) values(%s,%s,'Livre','Livre','Race class')", (classroom, school))
        db.execute("insert into public.admins(id,school_id,name,email,role,auth_user_id) values(%s,%s,'Race admin',%s,'ADMIN_B',%s)", (admin, school, f'{admin}@example.test', auth))
        if updating:
            for i, student in enumerate(student_ids):
                db.execute("insert into public.students(id,school_id,class_id,name,registration) values(%s,%s,%s,'Race student',%s)", (student, school, classroom, str(i)))
    try:
        def mutate(i):
            with psycopg.connect(URL) as db:
                db.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(auth),))
                db.execute('set local role authenticated')
                barrier.wait(timeout=10)
                try:
                    if updating:
                        result = db.execute("select public.update_admin_student_v1(%s,'Race student',null,'0007',%s,'ACTIVE')", (student_ids[i], classroom)).fetchone()[0]
                    else:
                        result = db.execute("select public.create_admin_student_v1('Race student',null,'0007',%s)", (classroom,)).fetchone()[0]
                    db.commit()
                    return result
                except psycopg.errors.UniqueViolation as error:
                    assert error.sqlstate == '23505'
                    assert error.diag.message_primary == 'ADMIN_REGISTRATION_CONFLICT'
                    db.rollback()
                    return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(mutate, [0, 1]))
        assert sum(result is not None for result in outcomes) == 1
        with psycopg.connect(URL) as db:
            assert db.execute("select count(*) from public.students where school_id=%s and registration='0007'", (school,)).fetchone() == (1,)
            assert db.execute('select count(*) from public.audit_logs where actor_id=%s', (admin,)).fetchone() == (1,)
    finally:
        with psycopg.connect(URL, autocommit=True) as db:
            db.execute('delete from public.audit_logs where school_id=%s', (school,))
            db.execute('delete from public.students where school_id=%s', (school,))
            db.execute('delete from public.classes where school_id=%s', (school,))
            db.execute('delete from public.admins where school_id=%s', (school,))
            db.execute('delete from public.schools where id=%s', (school,))
