"""Local management contracts and two A accounts contending for the domain lock."""
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
import psycopg
import pytest
from test_admin_binbazar_v1 import fixture, rpc, ROOT, URL

@pytest.fixture
def structure(fixture):
    c, i = fixture
    try:
        yield c, i
    finally:
        actors = [i['A'], i['B']]
        schools = [r[0] for r in c.execute("select entity_id from admin_structure_creation_receipts where entity_kind='SCHOOL' and created_by_admin_id=any(%s)", (actors,))]
        admins = [r[0] for r in c.execute("select entity_id from admin_structure_creation_receipts where entity_kind='ADMIN' and created_by_admin_id=any(%s)", (actors,))]
        c.execute("delete from admin_structure_creation_receipts where created_by_admin_id=any(%s)", (actors,))
        c.execute("delete from audit_logs where actor_id=any(%s) or school_id=any(%s)", (actors + admins, schools))
        c.execute("delete from admins where id=any(%s)", (admins,))
        c.execute("delete from schools where id=any(%s)", (schools,))

def create(i, actor='A', role='ADMIN_C', scope='school', status='ACTIVE', entity=None, email=None):
    entity = entity or uuid.uuid4()
    return rpc(i[actor], 'create_managed_admin_v1', entity, 'Created', email or f'{entity}@example.test', role, i[scope] if scope else None, status)[0][0]

def update(i, target, actor='A', status='INACTIVE', name='Updated', email=None):
    return rpc(i[actor], 'update_managed_admin_v1', target, name, email or f'{target}@example.test', status)[0][0]

def test_parity():
    assert (ROOT/'database/migrations/028_admin_structure_management_v1.sql').read_bytes() == (ROOT/'supabase/migrations/20261001130000_admin_structure_management_v1.sql').read_bytes()

def test_school_creation_counts_replay_conflict(structure):
    c,i=structure
    school=uuid.uuid4()
    assert rpc(i['A'],'create_admin_school_v1',school,'  School  ')[0][0]==school
    assert rpc(i['A'],'create_admin_school_v1',school,'School')[0][0]==school
    with pytest.raises(psycopg.errors.UniqueViolation,match='ID_CONFLICT'):
        rpc(i['A'],'create_admin_school_v1',school,'Other')
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        rpc(i['A'],'create_admin_school_v1',uuid.uuid4(),' \t\n')
    rows=rpc(i['A'],'get_admin_schools_v1')
    assert next(r for r in rows if r[0]==school)[2:]==(0,0,0,0)
    assert next(r for r in rows if r[0]==i['school'])[2:5]==(1,1,3)
    assert c.execute("select count(*) from audit_logs where school_id is null and action='ADMIN_SCHOOL_CREATED_V1' and metadata->>'school_id'=%s",(str(school),)).fetchone()[0]==1
    # Names are deliberately not globally unique.
    rpc(i['A'],'create_admin_school_v1',uuid.uuid4(),'School')

@pytest.mark.parametrize('actor',['B','C','inactive','unlinked'])
def test_global_school_denied(structure,actor):
    _,i=structure
    for name,args in [('get_admin_schools_v1',()),('create_admin_school_v1',(uuid.uuid4(),'School'))]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege): rpc(i[actor],name,*args)

@pytest.mark.parametrize('role,scope',[('ADMIN_A',None),('ADMIN_B','school'),('ADMIN_C','school')])
def test_a_creates_unlinked_identity_and_lists(structure,role,scope):
    c,i=structure
    target=create(i,role=role,scope=scope)
    assert c.execute('select auth_user_id,password_hash,school_id from admins where id=%s',(target,)).fetchone()==(None,None,i[scope] if scope else None)
    row=next(r for r in rpc(i['A'],'get_managed_admins_v1') if r[0]==target)
    assert row[3]==role and row[7] is False
    log=c.execute("select school_id,actor_id from audit_logs where action='MANAGED_ADMIN_CREATED_V1' and metadata->>'admin_id'=%s",(str(target),)).fetchone()
    assert log==(i[scope] if scope else None,i['A'])

def test_b_scope_and_immutable_authorization(structure):
    c,i=structure
    target=create(i,actor='B',scope=None)
    assert c.execute('select school_id,role from admins where id=%s',(target,)).fetchone()==(i['school'],'ADMIN_C')
    rows=rpc(i['B'],'get_managed_admins_v1')
    assert {r[0] for r in rows}=={i['C'],target}
    for role,scope in [('ADMIN_A',None),('ADMIN_B',None),('ADMIN_C','other_school')]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege): create(i,'B',role,scope)
    for victim in [i['A'],i['B'],i['external']]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege): update(i,victim,'B')
    c.execute("update admins set password_hash='legacy',auth_user_id=%s where id=%s",(target,target))
    update(i,target,'B')
    update(i,target,'B',status='ACTIVE')
    assert c.execute('select password_hash,auth_user_id,role,school_id from admins where id=%s',(target,)).fetchone()==('legacy',target,'ADMIN_C',i['school'])

@pytest.mark.parametrize('actor',['C','inactive','unlinked'])
def test_manager_denied(structure,actor):
    _,i=structure
    with pytest.raises(psycopg.errors.InsufficientPrivilege): rpc(i[actor],'get_managed_admins_v1')
    with pytest.raises(psycopg.errors.InsufficientPrivilege): create(i,actor)
    with pytest.raises(psycopg.errors.InsufficientPrivilege): update(i,i['C'],actor)

@pytest.mark.parametrize('role,scope',[('ADMIN_A','school'),('ADMIN_B',None),('ADMIN_C',None)])
def test_invalid_scope(structure,role,scope):
    _,i=structure
    with pytest.raises(psycopg.errors.InvalidParameterValue): create(i,role=role,scope=scope)

def test_duplicate_email_noop_and_original_receipt(structure):
    c,i=structure
    target=uuid.uuid4()
    create(i,entity=target)
    with pytest.raises(psycopg.errors.UniqueViolation,match='EMAIL_CONFLICT'): create(i,email=f'{target}@example.test')
    update(i,target)
    before=c.execute('select updated_at from admins where id=%s',(target,)).fetchone()
    update(i,target)
    assert c.execute('select updated_at from admins where id=%s',(target,)).fetchone()==before
    assert c.execute("select count(*) from audit_logs where action='MANAGED_ADMIN_UPDATED_V1' and metadata->>'admin_id'=%s",(str(target),)).fetchone()[0]==1
    assert create(i,entity=target)==target
    with pytest.raises(psycopg.errors.UniqueViolation,match='ID_CONFLICT'): create(i,entity=target,status='INACTIVE')
    with pytest.raises(psycopg.errors.UniqueViolation,match='EMAIL_CONFLICT'): update(i,target,email=f"{i['C']}@example.test")
    assert c.execute('select status from admins where id=%s',(target,)).fetchone()[0]=='INACTIVE'

def test_self_and_last_a_guards(structure):
    c,i=structure
    with pytest.raises(psycopg.errors.ObjectNotInPrerequisiteState,match='LAST_ACTIVE_A'): update(i,i['A'])
    create(i,role='ADMIN_A',scope=None)
    with pytest.raises(psycopg.errors.ObjectNotInPrerequisiteState,match='SELF_DEACTIVATION'): update(i,i['A'])

@pytest.mark.parametrize('winner',['first','second'])
@pytest.mark.parametrize('isolation',['READ COMMITTED','REPEATABLE READ'])
def test_two_a_cross_deactivation_is_serialized(structure,winner,isolation):
    c,i=structure
    second=create(i,role='ADMIN_A',scope=None)
    c.execute('update admins set auth_user_id=id where id=%s',(second,))
    actor,target=(i['A'],second) if winner=='first' else (second,i['A'])
    started=threading.Event()
    def call(tx,who,victim):
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(who),))
        tx.execute('set role authenticated')
        tx.execute("select update_managed_admin_v1(%s,'Updated',%s,'INACTIVE')",(victim,f'{victim}@example.test'))
    def compete():
        started.set()
        try:
            with psycopg.connect(URL) as tx:
                tx.execute(f'set transaction isolation level {isolation}')
                tx.execute("set local lock_timeout='10s'")
                call(tx,target,actor)
            return 'ok'
        except psycopg.Error as e: return e.sqlstate
    with psycopg.connect(URL) as first:
        call(first,actor,target)
        with ThreadPoolExecutor(max_workers=1) as pool:
            future=pool.submit(compete)
            assert started.wait(5)
            blocked=False
            for _ in range(100):
                blocked=c.execute("select exists(select 1 from pg_stat_activity where wait_event_type='Lock' and query like '%update_managed_admin_v1%')").fetchone()[0]
                if blocked: break
                threading.Event().wait(.02)
            first.commit()
            assert blocked
            assert future.result(timeout=15)==('42501' if isolation=='READ COMMITTED' else '40001')
    assert c.execute("select count(*) from admins where role='ADMIN_A' and status='ACTIVE'").fetchone()[0]==1
    assert c.execute("select count(*) from audit_logs where action='MANAGED_ADMIN_UPDATED_V1' and actor_id=any(%s)",([actor,target],)).fetchone()[0]==1
    # The winner can reactivate the other account.
    with psycopg.connect(URL) as tx:
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(actor),))
        tx.execute('set role authenticated')
        tx.execute("select update_managed_admin_v1(%s,'Updated',%s,'ACTIVE')",(target,f'{target}@example.test'))

@pytest.mark.parametrize('kind',['school','create','update'])
def test_audit_failure_is_atomic(structure,kind):
    c,i=structure
    with psycopg.connect(URL) as tx:
        tx.execute("create function pg_temp.fail_structure_audit() returns trigger language plpgsql as $$begin raise exception 'audit failure';end$$")
        tx.execute('create trigger test_structure_audit before insert on audit_logs for each row execute function pg_temp.fail_structure_audit()')
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(i['A']),))
        tx.execute('set role authenticated')
        with pytest.raises(psycopg.errors.RaiseException):
            if kind=='school': tx.execute("select create_admin_school_v1(%s,'Fail')",(uuid.uuid4(),))
            elif kind=='create': tx.execute("select create_managed_admin_v1(%s,'Fail','fail@example.test','ADMIN_A',null,'ACTIVE')",(uuid.uuid4(),))
            else: tx.execute("select update_managed_admin_v1(%s,'Fail',%s,'INACTIVE')",(i['C'],f"{i['C']}@example.test"))
        tx.rollback()
    assert c.execute("select count(*) from admin_structure_creation_receipts where created_by_admin_id=%s",(i['A'],)).fetchone()[0]==0
    assert c.execute('select status,name from admins where id=%s',(i['C'],)).fetchone()==('ACTIVE','C')
