"""Local-only contracts and real competing transactions for Admin BinBazar."""
import os
import threading
import uuid
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg
import pytest

URL = os.getenv("BINGO_TEST_DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
ROOT = Path(__file__).resolve().parents[2]


def test_migration_parity():
    assert (ROOT / "database/migrations/026_admin_binbazar_v1.sql").read_text() == (ROOT / "supabase/migrations/20260930150000_admin_binbazar_v1.sql").read_text()


@pytest.fixture
def fixture():
    # No silent skip: requested local database validation must actually run.
    assert urlparse(URL).hostname in ("127.0.0.1", "localhost"), "Local-only fixtures"
    connection = psycopg.connect(URL, autocommit=True)
    ids = {k: uuid.uuid4() for k in ["school", "other_school", "class", "other_class", "student", "student_auth", "reward", "other_reward", "other_student", "B", "C", "A", "inactive", "external", "unlinked"]}
    for key in ["school", "other_school"]:
        connection.execute("insert into schools(id,name) values(%s,%s)", (ids[key], key))
    for school, cls in [("school", "class"), ("other_school", "other_class")]:
        connection.execute("insert into classes(id,school_id,name,segment,grade) values(%s,%s,'Class','TEST','1')", (ids[cls], ids[school]))
    connection.execute("insert into students(id,school_id,class_id,name,auth_user_id,points_student_balance) values(%s,%s,%s,'Student',%s,1000)", (ids["student"], ids["school"], ids["class"], ids["student_auth"]))
    connection.execute("insert into students(id,school_id,class_id,name) values(%s,%s,%s,'External')", (ids["other_student"], ids["other_school"], ids["other_class"]))
    for key, school in [("reward", "school"), ("other_reward", "other_school")]:
        connection.execute("insert into rewards(id,school_id,name,cost_points,stock_qty,status) values(%s,%s,'Original snapshot',200,3,'DISABLED')", (ids[key], ids[school]))
    for key, role, status, school in [("B", "ADMIN_B", "ACTIVE", "school"), ("C", "ADMIN_C", "ACTIVE", "school"), ("A", "ADMIN_A", "ACTIVE", None), ("inactive", "ADMIN_B", "INACTIVE", "school"), ("external", "ADMIN_C", "ACTIVE", "other_school")]:
        connection.execute("insert into admins(id,auth_user_id,school_id,name,email,role,status) values(%s,%s,%s,%s,%s,%s,%s)", (ids[key], ids[key], ids[school] if school else None, key, f"{ids[key]}@example.test", role, status))
    try:
        yield connection, ids
    finally:
        for table in ["audit_logs", "redemptions", "rewards", "students", "classes", "admins"]:
            connection.execute(f"delete from {table} where school_id=any(%s)", ([ids["school"], ids["other_school"]],))
        connection.execute("delete from admins where id=%s", (ids["A"],))
        connection.execute("delete from schools where id=any(%s)", ([ids["school"], ids["other_school"]],))
        connection.close()


def rpc(auth, function, *args):
    with psycopg.connect(URL) as c:
        c.execute("select set_config('request.jwt.claim.sub',%s,false)", (str(auth),))
        c.execute("set role authenticated")
        return c.execute(f"select * from public.{function}({','.join(['%s'] * len(args))})", args).fetchall()


def order(ids):
    return rpc(ids["student_auth"], "request_redemption_v1", uuid.uuid4(), ids["reward"])[0][0]


@pytest.mark.parametrize("role", ["B", "C"])
def test_reads_updates_scope_and_snapshots(fixture, role):
    c, i = fixture
    redemption = order(i)
    products = rpc(i[role], "get_admin_binbazar_products_v1")
    assert len(products) == 1 and products[0][0] == i["reward"]
    # Legacy rewards.status DISABLED is not availability authority.
    rpc(i[role], "update_admin_binbazar_product_v1", i["reward"], "Changed", "Description", None, False)
    assert c.execute("select name,cost_points,stock_qty,is_active,status from rewards where id=%s", (i["reward"],)).fetchone() == ("Changed", 200, None, False, "DISABLED")
    rpc(i[role], "update_admin_binbazar_product_v1", i["reward"], "Changed", None, 0, True)
    rows = rpc(i[role], "get_admin_redemptions_v1")
    assert len(rows) == 1 and rows[0][0] == redemption and rows[0][9:11] == ("Original snapshot", 200)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        rpc(i[role], "update_admin_binbazar_product_v1", i["other_reward"], "Forged", None, 1, True)
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        rpc(i[role], "update_admin_binbazar_product_v1", i["reward"], "  ", None, 0, True)
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        rpc(i[role], "update_admin_binbazar_product_v1", i["reward"], "X", None, -1, True)
    assert rpc(i["external"], "get_admin_redemptions_v1") == []
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        rpc(i["external"], "deliver_admin_redemption_v1", redemption)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        rpc(i["external"], "cancel_admin_redemption_v1", redemption)
    assert c.execute("select count(*) from audit_logs where school_id=%s and action='ADMIN_PRODUCT_UPDATED_V1'", (i["school"],)).fetchone()[0] == 2


@pytest.mark.parametrize("role", ["A", "inactive", "unlinked"])
@pytest.mark.parametrize("function", ["get_admin_binbazar_products_v1", "get_admin_redemptions_v1", "deliver_admin_redemption_v1", "cancel_admin_redemption_v1", "update_admin_binbazar_product_v1"])
def test_denied_identities(fixture, role, function):
    _, i = fixture
    args = [] if function.startswith("get_") else [i["reward"], "X", None, None, True] if function.startswith("update_") else [uuid.uuid4()]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        rpc(i[role], function, *args)


@pytest.mark.parametrize("role", ["B", "C"])
@pytest.mark.parametrize("action", ["deliver", "cancel"])
def test_terminal_retries_and_exact_economy(fixture, role, action):
    c, i = fixture
    redemption = order(i)
    history = c.execute("select jsonb_agg(to_jsonb(d) order by id) from deposits d").fetchone()[0]
    for _ in range(2):
        assert rpc(i[role], f"{action}_admin_redemption_v1", redemption)[0][0] == redemption
    expected = ("DELIVERED", 800, 2) if action == "deliver" else ("CANCELED", 1000, 3)
    assert snapshot(c, i, redemption) == expected
    row = c.execute("select delivered_at,canceled_at,delivered_by_admin_id from redemptions where id=%s", (redemption,)).fetchone()
    assert row[0] is not None if action == "deliver" else row[1] is not None
    assert row[2] == (i[role] if action == "deliver" else None)
    assert c.execute("select count(*) from audit_logs where school_id=%s and action like 'ADMIN_REDEMPTION_%%'", (i["school"],)).fetchone()[0] == 1
    assert c.execute("select jsonb_agg(to_jsonb(d) order by id) from deposits d").fetchone()[0] == history
    other = "C" if role == "B" else "B"
    rpc(i[other], f"{action}_admin_redemption_v1", redemption)
    assert c.execute("select delivered_by_admin_id from redemptions where id=%s", (redemption,)).fetchone()[0] == (i[role] if action == "deliver" else None)
    opposite = "cancel" if action == "deliver" else "deliver"
    with pytest.raises(psycopg.errors.ObjectNotInPrerequisiteState):
        rpc(i[role], f"{opposite}_admin_redemption_v1", redemption)
    # History is exposed with terminal state and original snapshots.
    assert rpc(i[role], "get_admin_redemptions_v1")[0][2] == expected[0]


def snapshot(c, i, redemption):
    return c.execute("select r.status,s.points_student_balance,w.stock_qty from redemptions r join students s on s.id=r.student_id join rewards w on w.id=r.reward_id where r.id=%s", (redemption,)).fetchone()


@pytest.mark.parametrize("original_finite", [True, False])
def test_unlimited_cancellation(fixture, original_finite):
    c, i = fixture
    if not original_finite:
        c.execute("update rewards set stock_qty=null where id=%s", (i["reward"],))
    redemption = order(i)
    rpc(i["C"], "update_admin_binbazar_product_v1", i["reward"], "New name", None, None, True)
    rpc(i["C"], "cancel_admin_redemption_v1", redemption)
    assert snapshot(c, i, redemption) == ("CANCELED", 1000, None)
    assert rpc(i["B"], "get_admin_redemptions_v1")[0][9:11] == ("Original snapshot", 200)


@pytest.mark.parametrize("mobile", [False, True])
@pytest.mark.parametrize("winner", ["deliver", "cancel"])
def test_competing_transactions(fixture, mobile, winner):
    c, i = fixture
    redemption = order(i)
    cancel_fn = "cancel_my_redemption_v1" if mobile else "cancel_admin_redemption_v1"
    cancel_auth = i["student_auth"] if mobile else i["C"]
    functions = {"deliver": (i["B"], "deliver_admin_redemption_v1"), "cancel": (cancel_auth, cancel_fn)}
    loser = "cancel" if winner == "deliver" else "deliver"
    # Winner holds the actual redemption lock while opponent runs and waits.
    with psycopg.connect(URL) as first:
        auth, fn = functions[winner]
        first.execute("select set_config('request.jwt.claim.sub',%s,false)", (str(auth),))
        first.execute("set role authenticated")
        first.execute(f"select * from public.{fn}(%s)", (redemption,)).fetchall()
        started = threading.Event()
        def competing():
            started.set()
            try:
                rpc(functions[loser][0], functions[loser][1], redemption)
                return "ok"
            except psycopg.Error as e:
                return e.sqlstate
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(competing)
            assert started.wait(5)
            # Confirm a real blocked transaction, not just thread scheduling.
            for _ in range(100):
                blocked = c.execute("select count(*) from pg_stat_activity where wait_event_type='Lock' and query like %s", (f"%{functions[loser][1]}%",)).fetchone()[0]
                if blocked:
                    break
                threading.Event().wait(.02)
            first.commit()  # Always release before asserting, including diagnostic failures.
            assert blocked == 1
            assert future.result(timeout=10) == "55000"
    assert snapshot(c, i, redemption) == (("DELIVERED", 800, 2) if winner == "deliver" else ("CANCELED", 1000, 3))
    rpc(functions[winner][0], functions[winner][1], redemption)
    assert c.execute("select count(*) from audit_logs where school_id=%s and (action like 'ADMIN_REDEMPTION_%%' or action='REDEMPTION_CANCELED_V1')", (i["school"],)).fetchone()[0] == 1


@pytest.mark.parametrize("operation", ["cancel", "deliver", "product"])
def test_audit_failure_rolls_back_mutation(fixture, operation):
    c, i = fixture
    redemption = order(i)
    # Transaction-local trigger, removed by rollback; no shared schema pollution.
    with psycopg.connect(URL) as tx:
        tx.execute("create function pg_temp.fail_audit() returns trigger language plpgsql as $$begin raise exception 'audit failure'; end$$")
        tx.execute("create trigger test_admin_binbazar_audit before insert on audit_logs for each row execute function pg_temp.fail_audit()")
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)", (str(i["B"]),))
        tx.execute("set role authenticated")
        with pytest.raises(psycopg.errors.RaiseException):
            if operation == "product":
                tx.execute("select update_admin_binbazar_product_v1(%s,'Changed',null,null,false)", (i["reward"],))
            else:
                tx.execute(f"select {operation}_admin_redemption_v1(%s)", (redemption,))
        tx.rollback()
    assert snapshot(c, i, redemption) == ("PENDING", 800, 2)
    assert c.execute("select name,is_active from rewards where id=%s", (i["reward"],)).fetchone() == ("Original snapshot", True)


def test_unlimited_snapshot_does_not_restore_new_finite_stock(fixture):
    c, i = fixture
    c.execute("update rewards set stock_qty=null where id=%s", (i["reward"],))
    redemption = order(i)
    rpc(i["B"], "update_admin_binbazar_product_v1", i["reward"], "Finite now", None, 5, True)
    rpc(i["C"], "cancel_admin_redemption_v1", redemption)
    assert snapshot(c, i, redemption) == ("CANCELED", 1000, 5)


def test_legacy_without_snapshot_is_not_refunded_from_current_price(fixture):
    c, i = fixture
    redemption = uuid.uuid4()
    c.execute("insert into redemptions(id,school_id,student_id,reward_id,status,code) values(%s,%s,%s,%s,'PENDING',%s)", (redemption,i["school"],i["student"],i["reward"],f"LEGACY-{redemption}"))
    assert rpc(i["C"], "get_admin_redemptions_v1")[0][9:11] == (None,None)
    with pytest.raises(psycopg.errors.RaiseException):
        rpc(i["C"], "cancel_admin_redemption_v1", redemption)
    assert snapshot(c, i, redemption) == ("PENDING",1000,3)


def test_inconsistent_legacy_school_relations_fail_closed(fixture):
    c, i = fixture
    redemption = uuid.uuid4()
    c.execute("insert into redemptions(id,school_id,student_id,reward_id,status,code,reward_name_snapshot,cost_points_snapshot,stock_was_finite) values(%s,%s,%s,%s,'PENDING',%s,'Original',200,true)", (redemption,i["school"],i["other_student"],i["other_reward"],f"LEGACY-{redemption}"))
    assert rpc(i["C"], "get_admin_redemptions_v1") == []
    for operation in ["deliver", "cancel"]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            rpc(i["C"], f"{operation}_admin_redemption_v1", redemption)
    assert c.execute("select status from redemptions where id=%s", (redemption,)).fetchone()[0] == "PENDING"
