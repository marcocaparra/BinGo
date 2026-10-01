"""Provas concorrentes reais de idempotencia/locking no PostgreSQL local."""
import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest

ROOT = Path(__file__).resolve().parents[2]
URL = os.getenv('BINGO_RPC_TEST_DATABASE_URL')


def test_request_migration_tracks_match():
    assert (ROOT / 'database/migrations/025_class_change_requests_v1.sql').read_text(encoding='utf-8') == (ROOT / 'supabase/migrations/20260930140000_class_change_requests_v1.sql').read_text(encoding='utf-8')


@pytest.fixture
def domain():
    if not URL:
        pytest.skip('Defina BINGO_RPC_TEST_DATABASE_URL para concorrencia PostgreSQL local.')
    school, student, b, c, auth_b, auth_c = [uuid.uuid4() for _ in range(6)]
    classes = [uuid.uuid4() for _ in range(3)]
    with psycopg.connect(URL, autocommit=True) as db:
        db.execute("insert into public.schools(id,name) values(%s,'Request race')", (school,))
        for i, classroom in enumerate(classes):
            db.execute("insert into public.classes(id,school_id,segment,grade,name) values(%s,%s,'Livre',%s,%s)", (classroom, school, str(i), f'Class {i}'))
        db.execute("insert into public.students(id,school_id,class_id,name,registration) values(%s,%s,%s,'Race student','001')", (student, school, classes[0]))
        for admin, auth, role in [(b, auth_b, 'ADMIN_B'), (c, auth_c, 'ADMIN_C')]:
            db.execute("insert into public.admins(id,school_id,name,email,role,auth_user_id) values(%s,%s,'Race admin',%s,%s,%s)", (admin, school, f'{admin}@example.test', role, auth))
    try:
        yield dict(school=school, student=student, classes=classes, b=b, c=c, auth_b=auth_b, auth_c=auth_c)
    finally:
        with psycopg.connect(URL, autocommit=True) as db:
            for table in ['class_change_requests', 'audit_logs', 'students', 'classes', 'admins']:
                db.execute(f'delete from public.{table} where school_id=%s', (school,))
            db.execute('delete from public.schools where id=%s', (school,))


def call(domain, auth_key, query, params, barrier=None):
    with psycopg.connect(URL) as db:
        db.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(domain[auth_key]),))
        db.execute('set local role authenticated')
        if barrier:
            barrier.wait(timeout=10)
        try:
            result = db.execute(query, params).fetchone()[0]
            db.commit()
            return ('ok', result)
        except (psycopg.errors.UniqueViolation, psycopg.errors.RaiseException) as error:
            db.rollback()
            return (error.sqlstate, error.diag.message_primary)


@pytest.mark.parametrize('divergent', [False, True], ids=['identical-replay', 'divergent-payload'])
def test_concurrent_creation(domain, divergent):
    request = uuid.uuid4()
    barrier = threading.Barrier(2)
    def create(i):
        destination = domain['classes'][2 if divergent and i else 1]
        return call(domain, 'auth_c', 'select public.create_class_change_request_v1(%s,%s,%s)', (request, domain['student'], destination), barrier)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(create, [0, 1]))
    assert sum(r[0] == 'ok' for r in results) == (1 if divergent else 2)
    if divergent:
        assert ('23505', 'CLASS_CHANGE_REQUEST_ID_CONFLICT') in results
    else:
        assert results == [('ok', request), ('ok', request)]
    with psycopg.connect(URL) as db:
        assert db.execute('select count(*) from public.class_change_requests where id=%s', (request,)).fetchone() == (1,)
        assert db.execute('select count(*) from public.audit_logs where school_id=%s', (domain['school'],)).fetchone() == (1,)
        assert db.execute('select class_id from public.students where id=%s', (domain['student'],)).fetchone() == (domain['classes'][0],)


@pytest.mark.parametrize('actions', [('approve', 'reject'), ('approve', 'cancel'), ('reject', 'cancel'), ('approve', 'reject', 'cancel')])
def test_competing_decisions_have_one_terminal_transition(domain, actions):
    request = uuid.uuid4()
    assert call(domain, 'auth_c', 'select public.create_class_change_request_v1(%s,%s,%s)', (request, domain['student'], domain['classes'][1])) == ('ok', request)
    barrier = threading.Barrier(len(actions))
    def decide(action):
        return action, call(domain, 'auth_c' if action == 'cancel' else 'auth_b', f'select public.{action}_class_change_request_v1(%s)', (request,), barrier)
    with ThreadPoolExecutor(max_workers=len(actions)) as pool:
        results = list(pool.map(decide, actions))
    winners = [a for a, r in results if r[0] == 'ok']
    assert len(winners) == 1
    assert all(r == ('P0001', 'CLASS_CHANGE_DECISION_CONFLICT') for a, r in results if a != winners[0])
    winner = winners[0]
    assert call(domain, 'auth_c' if winner == 'cancel' else 'auth_b', f'select public.{winner}_class_change_request_v1(%s)', (request,)) == ('ok', request)
    with psycopg.connect(URL) as db:
        assert db.execute('select status from public.class_change_requests where id=%s', (request,)).fetchone() == ({'approve': 'APPROVED', 'reject': 'REJECTED', 'cancel': 'CANCELED'}[winner],)
        assert db.execute('select class_id from public.students where id=%s', (domain['student'],)).fetchone() == (domain['classes'][1 if winner == 'approve' else 0],)
        assert db.execute('select count(*) from public.audit_logs where school_id=%s', (domain['school'],)).fetchone() == (2,)


def test_two_requests_cannot_both_overwrite_same_student(domain):
    requests = [uuid.uuid4(), uuid.uuid4()]
    for i, request in enumerate(requests):
        assert call(domain, 'auth_c', 'select public.create_class_change_request_v1(%s,%s,%s)', (request, domain['student'], domain['classes'][i + 1])) == ('ok', request)
    barrier = threading.Barrier(2)
    def approve(request):
        return call(domain, 'auth_b', 'select public.approve_class_change_request_v1(%s)', (request,), barrier)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(approve, requests))
    assert sum(r[0] == 'ok' for r in results) == 1
    assert ('P0001', 'CLASS_CHANGE_REQUEST_STALE') in results
    with psycopg.connect(URL) as db:
        assert db.execute("select count(*) from public.class_change_requests where school_id=%s and status='APPROVED'", (domain['school'],)).fetchone() == (1,)
        assert db.execute('select count(*) from public.audit_logs where school_id=%s', (domain['school'],)).fetchone() == (3,)


def test_creation_captures_source_serialized_with_direct_b_change(domain):
    request = uuid.uuid4()
    barrier = threading.Barrier(2)
    def run(action):
        if action == 'create':
            return call(domain, 'auth_c', 'select public.create_class_change_request_v1(%s,%s,%s)', (request, domain['student'], domain['classes'][1]), barrier)
        return call(domain, 'auth_b', "select public.update_admin_student_v1(%s,'Race student',null,'001',%s,'ACTIVE')", (domain['student'], domain['classes'][2]), barrier)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(run, ['create', 'update']))
    assert all(r[0] == 'ok' for r in results)
    with psycopg.connect(URL) as db:
        source = db.execute('select source_class_id from public.class_change_requests where id=%s', (request,)).fetchone()[0]
        assert source in (domain['classes'][0], domain['classes'][2])
        assert db.execute('select class_id from public.students where id=%s', (domain['student'],)).fetchone() == (domain['classes'][2],)
    outcome = call(domain, 'auth_b', 'select public.approve_class_change_request_v1(%s)', (request,))
    assert outcome == (('P0001', 'CLASS_CHANGE_REQUEST_STALE') if source == domain['classes'][0] else ('ok', request))
