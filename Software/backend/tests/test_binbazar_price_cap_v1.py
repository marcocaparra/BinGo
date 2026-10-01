"""Global cap contracts, immutable create intents, and real row-lock races."""
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor
import psycopg
import pytest
from test_admin_binbazar_v1 import fixture, rpc, order, URL, ROOT


@pytest.fixture
def settings_fixture(fixture):
    c, i = fixture
    original = c.execute("select binbazar_max_price,created_at,updated_at from global_economic_settings where id").fetchone()
    try:
        yield c, i
    finally:
        c.execute("delete from audit_logs where actor_id=%s and school_id is null", (i["A"],))
        c.execute("update global_economic_settings set binbazar_max_price=%s,created_at=%s,updated_at=%s where id", original)


def cap(i, value=1500):
    return rpc(i["A"], "update_binbazar_price_cap_v1", value)[0][0]


def create(i, role="B", price=1200, product=None, name="New", stock=None):
    product = product or uuid.uuid4()
    return rpc(i[role], "create_admin_binbazar_product_v1", product, name, "Description", "Category", price, stock, True)[0][0]


def update(i, price, role="B", product=None, name="Changed", stock=None):
    return rpc(i[role], "update_admin_binbazar_product_v1", product or i["reward"], name, "Description", stock, True, price, "Category")[0][0]


def test_migration_parity():
    assert (ROOT / "database/migrations/027_binbazar_global_price_cap_v1.sql").read_bytes() == (ROOT / "supabase/migrations/20261001120000_binbazar_global_price_cap_v1.sql").read_bytes()


@pytest.mark.parametrize("role", ["A", "B", "C"])
def test_cap_read(settings_fixture, role):
    c, i = settings_fixture
    assert rpc(i[role], "get_binbazar_price_cap_v1") == [(None,)]
    assert cap(i) == 1500
    assert rpc(i[role], "get_binbazar_price_cap_v1") == [(1500,)]


@pytest.mark.parametrize("role", ["B", "C", "inactive", "unlinked"])
def test_cap_write_denied(settings_fixture, role):
    _, i = settings_fixture
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        rpc(i[role], "update_binbazar_price_cap_v1", 1500)
    if role in ("inactive", "unlinked"):
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            rpc(i[role], "get_binbazar_price_cap_v1")


@pytest.mark.parametrize("value", [0, -1, None])
def test_invalid_cap(settings_fixture, value):
    _, i = settings_fixture
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        cap(i, value)


def test_global_audit_and_noop(settings_fixture):
    c, i = settings_fixture
    cap(i)
    first = c.execute("select updated_at from global_economic_settings where id").fetchone()
    cap(i)
    assert c.execute("select updated_at from global_economic_settings where id").fetchone() == first
    logs = c.execute("select school_id,actor_type,actor_id,metadata from audit_logs where action='BINBAZAR_PRICE_CAP_UPDATED_V1' and actor_id=%s", (i["A"],)).fetchall()
    assert logs == [(None, "ADMIN", i["A"], {"old_max_price": None, "new_max_price": 1500})]
    cap(i, 1000)
    assert c.execute("select count(*) from audit_logs where actor_id=%s and school_id is null", (i["A"],)).fetchone()[0] == 2


@pytest.mark.parametrize("role", ["B", "C"])
@pytest.mark.parametrize("price", [1, 1500])
def test_create_within_cap(settings_fixture, role, price):
    c, i = settings_fixture
    cap(i)
    product = create(i, role, price)
    assert c.execute("select school_id,cost_points,stock_qty,is_active,created_by_admin_id from rewards where id=%s", (product,)).fetchone() == (i["school"], price, None, True, i[role])
    assert product in [r[0] for r in rpc(i[role], "get_admin_binbazar_products_v1")]
    assert product not in [r[0] for r in rpc(i["external"], "get_admin_binbazar_products_v1")]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        update(i, price, "external", product)


@pytest.mark.parametrize("role", ["A", "inactive", "unlinked"])
def test_create_denied(settings_fixture, role):
    _, i = settings_fixture
    cap(i)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        create(i, role)


def test_unconfigured_and_excessive_prices(settings_fixture):
    c, i = settings_fixture
    with pytest.raises(psycopg.errors.ObjectNotInPrerequisiteState, match="UNCONFIGURED"):
        create(i)
    with pytest.raises(psycopg.errors.ObjectNotInPrerequisiteState, match="UNCONFIGURED"):
        update(i, 1200)
    # Non-price editing stays safe even before first configuration.
    update(i, 200)
    cap(i)
    with pytest.raises(psycopg.errors.InvalidParameterValue, match="EXCEEDED"):
        create(i, price=1501)
    with pytest.raises(psycopg.errors.InvalidParameterValue, match="EXCEEDED"):
        update(i, 1501)
    for invalid in [0, -1]:
        with pytest.raises(psycopg.errors.InvalidParameterValue):
            create(i, price=invalid)
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        create(i, name="   ")
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        create(i, stock=-1)
    assert c.execute("select count(*) from rewards where created_by_admin_id=%s", (i["B"],)).fetchone()[0] == 0


def test_reduction_does_not_retroact(settings_fixture):
    c, i = settings_fixture
    cap(i)
    update(i, 1400, stock=4)
    c.execute("update students set points_student_balance=5000 where id=%s", (i["student"],))
    redemption = order(i)
    before = c.execute("select to_jsonb(r) from redemptions r where id=%s", (redemption,)).fetchone()[0]
    economy = c.execute("select points_student_balance from students where id=%s", (i["student"],)).fetchone()
    cap(i, 1000)
    assert c.execute("select cost_points,is_active,stock_qty from rewards where id=%s", (i["reward"],)).fetchone() == (1400, True, 3)
    assert c.execute("select to_jsonb(r) from redemptions r where id=%s", (redemption,)).fetchone()[0] == before
    assert c.execute("select points_student_balance from students where id=%s", (i["student"],)).fetchone() == economy
    update(i, 1400, name="Historical still allowed", stock=3)
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        update(i, 1300)
    update(i, 1000)
    assert c.execute("select cost_points_snapshot from redemptions where id=%s", (redemption,)).fetchone()[0] == 1400


def test_create_replay_survives_edits_stock_and_cap_reduction(settings_fixture):
    c, i = settings_fixture
    cap(i)
    product = uuid.uuid4()
    create(i, product=product)
    update(i, 1300, product=product, name="Edited", stock=2)
    cap(i, 1000)
    assert create(i, product=product) == product
    assert c.execute("select name,cost_points,stock_qty from rewards where id=%s", (product,)).fetchone() == ("Edited", 1300, 2)
    assert c.execute("select count(*) from audit_logs where action='ADMIN_PRODUCT_CREATED_V1' and metadata->>'reward_id'=%s", (str(product),)).fetchone()[0] == 1
    for payload in [{"price": 1100}, {"name": "Different"}, {"role": "C"}]:
        with pytest.raises(psycopg.errors.UniqueViolation, match="ID_CONFLICT"):
            create(i, product=product, **payload)


def test_update_noop_does_not_change_timestamp_or_audit(settings_fixture):
    c, i = settings_fixture
    cap(i)
    update(i, 1000)
    first = c.execute("select updated_at,admin_creation_payload from rewards where id=%s", (i["reward"],)).fetchone()
    update(i, 1000)
    assert c.execute("select updated_at,admin_creation_payload from rewards where id=%s", (i["reward"],)).fetchone() == first
    assert c.execute("select count(*) from audit_logs where school_id=%s and action='ADMIN_PRODUCT_UPDATED_V1'", (i["school"],)).fetchone()[0] == 1


@pytest.mark.parametrize("operation", ["create", "update"])
@pytest.mark.parametrize("winner", ["product", "cap"])
def test_price_change_vs_cap_serializes(settings_fixture, operation, winner):
    c, i = settings_fixture
    cap(i)
    product = uuid.uuid4() if operation == "create" else i["reward"]
    def call(tx, kind):
        auth = i["A"] if kind == "cap" else i["B"]
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)", (str(auth),))
        tx.execute("set role authenticated")
        if kind == "cap":
            tx.execute("select update_binbazar_price_cap_v1(1000)")
        elif operation == "create":
            tx.execute("select create_admin_binbazar_product_v1(%s,'Race',null,null,1200,null,true)", (product,))
        else:
            tx.execute("select update_admin_binbazar_product_v1(%s,'Race',null,null,true,1200,null)", (product,))
    loser = "cap" if winner == "product" else "product"
    started = threading.Event()
    def competing():
        started.set()
        try:
            with psycopg.connect(URL) as tx:
                tx.execute("set local lock_timeout='10s'")
                call(tx, loser)
            return "ok"
        except psycopg.Error as e:
            return e.sqlstate
    with psycopg.connect(URL) as first:
        call(first, winner)
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(competing)
            assert started.wait(5)
            blocked = 0
            for _ in range(100):
                blocked = c.execute("select count(*) from pg_stat_activity where wait_event_type='Lock' and query like '%binbazar%'").fetchone()[0]
                if blocked: break
                threading.Event().wait(.02)
            first.commit()
            assert blocked >= 1
            assert future.result(timeout=15) == ("ok" if winner == "product" else "22023")
    assert rpc(i["B"], "get_binbazar_price_cap_v1") == [(1000,)]
    row = c.execute("select cost_points from rewards where id=%s", (product,)).fetchone()
    assert row == ((1200,) if winner == "product" else None if operation == "create" else (200,))


@pytest.mark.parametrize("operation", ["cap", "create", "update"])
def test_audit_failure_rolls_back(settings_fixture, operation):
    c, i = settings_fixture
    cap(i)
    product = uuid.uuid4()
    with psycopg.connect(URL) as tx:
        tx.execute("create function pg_temp.fail_cap_audit() returns trigger language plpgsql as $$begin raise exception 'audit failure'; end$$")
        tx.execute("create trigger test_cap_audit before insert on audit_logs for each row execute function pg_temp.fail_cap_audit()")
        tx.execute("select set_config('request.jwt.claim.sub',%s,false)", (str(i["A"] if operation == "cap" else i["B"]),))
        tx.execute("set role authenticated")
        with pytest.raises(psycopg.errors.RaiseException):
            if operation == "cap": tx.execute("select update_binbazar_price_cap_v1(1000)")
            elif operation == "create": tx.execute("select create_admin_binbazar_product_v1(%s,'New',null,null,1000,null,true)", (product,))
            else: tx.execute("select update_admin_binbazar_product_v1(%s,'Updated',null,null,true,1000,null)", (i["reward"],))
        tx.rollback()
    assert rpc(i["A"], "get_binbazar_price_cap_v1") == [(1500,)]
    assert c.execute("select cost_points from rewards where id=%s", (i["reward"],)).fetchone() == (200,)
    assert c.execute("select count(*) from rewards where id=%s", (product,)).fetchone()[0] == 0
