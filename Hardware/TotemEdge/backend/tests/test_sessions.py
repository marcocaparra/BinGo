"""Contratos/estados de software: nenhuma implementação ou simulação de controller."""

import asyncio
import json
import sqlite3
from types import SimpleNamespace
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from fastapi.testclient import TestClient

from app.central_contracts import DepositPayload
from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import CycleError
from app.main import create_app
from app.services.sessions import SessionService
from app.storage import CycleStore

CLASS = UUID("00000000-0000-4000-8000-000000000010")
STUDENT = UUID("00000000-0000-4000-8000-000000000011")


def context_body():
    return {
        "school": {"id": str(uuid4()), "name": "Escola"},
        "machine": {"id": "00000000-0000-4000-8000-000000000001", "name": "Totem"},
        "classes": [
            {
                "id": str(CLASS),
                "name": "7 A",
                "segment": "Fundamental II",
                "grade": "7",
                "points_class_balance": 0,
            }
        ],
        "students": [
            {
                "id": str(STUDENT),
                "name": "Aluno",
                "class_id": str(CLASS),
                "class_name": "7 A",
                "status": "ACTIVE",
                "points_student_balance": 0,
                "pin_hash": "never-forward",
            }
        ],
        "api_key": "never-forward",
    }


def pin_body():
    return {
        "confirmed": True,
        "student": {
            "id": str(STUDENT),
            "name": "Aluno",
            "class_id": str(CLASS),
            "class_name": "7 A",
            "pin_hash": "never-forward",
        },
        "token": "never-forward",
    }


def receipt(payload):
    return {
        "id": "00000000-0000-4000-8000-000000000020",
        "event_id": payload["event_id"],
        "waste_category_code": payload["waste_category_code"],
        "category_source": payload["category_source"],
        "bonus_rate_applied": "0.0000",
        "bonus_bincoins_awarded": 0,
        "points_awarded_student": 0,
        "points_awarded_class": 1900,
        "created_at": "2026-10-08T12:00:00Z",
    }


class LogicalReadinessFixture:
    async def check_status(self):
        # Só para identificação/triagem lógica: não representa homologação física.
        return SimpleNamespace(local=SimpleNamespace(can_start_deposit=True))


@pytest.fixture
def logical_service(tmp_path, configured_environment):
    requests = []

    def upstream(request):
        requests.append(request)
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=context_body())
        if request.url.path.endswith("totem-student-pin-v1"):
            body = json.loads(request.content)
            if body["pin"] == "0012":
                return httpx.Response(200, json=pin_body())
            return httpx.Response(
                401,
                json={"error": {"code": "STUDENT_PIN_INVALID", "private": body["pin"]}},
            )
        return httpx.Response(500, json={})

    http = httpx.AsyncClient(transport=httpx.MockTransport(upstream))
    store = CycleStore(tmp_path / "cycles.sqlite3")
    service = SessionService(store, SupabaseEdgeClient(http), LogicalReadinessFixture())
    yield service, requests
    store.close()
    asyncio.run(http.aclose())


@pytest.mark.anyio
async def test_correct_and_incorrect_pin_are_central_only(logical_service):
    service, requests = logical_service
    session = await service.start(uuid4(), "student", CLASS)
    with pytest.raises(CentralError, match="central") as error:
        await service.identify(session.event_id, STUDENT, "9999")
    assert error.value.code == "STUDENT_PIN_INVALID"
    assert service.store.get(session.event_id).state == "IDENTIFYING"
    identified = await service.identify(session.event_id, STUDENT, "0012")
    assert identified.state == "SAFETY"
    assert identified.student_id == STUDENT
    with pytest.raises(CycleError):
        await service.identify(session.event_id, STUDENT, "0012")
    assert len(requests) == 3
    with sqlite3.connect(service.store.path) as conn:
        data = repr(
            conn.execute(
                "SELECT class_name,student_name,payload,receipt,failure_code,vision_result FROM cycles"
            ).fetchall()
        ) + repr(conn.execute("SELECT code FROM transitions").fetchall())
        assert "pin" not in {
            column[1] for column in conn.execute("PRAGMA table_info(cycles)")
        }
    assert "0012" not in data and "9999" not in data and "never-forward" not in data


@pytest.mark.anyio
async def test_start_idempotent_and_one_active_cycle(logical_service):
    service, requests = logical_service
    key = uuid4()
    session = await service.start(key, "class_only", CLASS)
    same = await service.start(key, "class_only", CLASS)
    assert same.event_id == session.event_id
    assert len(requests) == 1
    with pytest.raises(CycleError) as error:
        await service.start(key, "student", CLASS)
    assert error.value.code == "COMMAND_ID_CONFLICT"
    with pytest.raises(CycleError) as error:
        await service.start(uuid4(), "class_only", CLASS)
    assert error.value.code == "SESSION_ALREADY_ACTIVE"


@pytest.mark.anyio
async def test_triage_records_block_and_rejects_duplicate(logical_service):
    service, _ = logical_service
    session = await service.start(uuid4(), "class_only", CLASS)
    result = service.safety(session.event_id, False)
    assert result.state == "PHYSICAL_BLOCKED"
    assert result.receipt is None
    with pytest.raises(CycleError):
        service.safety(session.event_id, False)
    assert service.cancel(session.event_id).state == "CANCELLED"
    assert service.cancel(session.event_id).state == "CANCELLED"


@pytest.mark.anyio
async def test_risk_cancels_without_registration(logical_service):
    service, requests = logical_service
    session = await service.start(uuid4(), "class_only", CLASS)
    assert service.safety(session.event_id, True).failure_code == "SAFETY_RISK"
    assert service.store.active() is None
    assert len(requests) == 1


def test_unavailable_routes_do_not_start_or_authenticate(
    configured_environment, healthy_body
):
    calls = []

    def upstream(request):
        calls.append(request.url.path)
        return httpx.Response(200, json=healthy_body)

    with TestClient(
        create_app(transport=httpx.MockTransport(upstream)),
        base_url="http://127.0.0.1",
        headers={"X-Totem-Request": "1"},
    ) as client:
        assert client.get("/local/status").json()["can_start_deposit"] is False
        response = client.post(
            "/local/sessions",
            json={
                "command_id": str(uuid4()),
                "class_id": str(CLASS),
                "mode": "student",
            },
        )
        assert response.status_code == 503
        assert client.get("/local/sessions/active").json() == {"session": None}
        assert client.get("/local/context").status_code == 503
        assert all(path.endswith("health-v1") for path in calls)


def test_local_routes_pin_validation_and_sanitized_projection(configured_environment):
    requests = []

    def upstream(request):
        requests.append(request)
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=context_body())
        return httpx.Response(200, json=pin_body())

    with TestClient(
        create_app(transport=httpx.MockTransport(upstream)),
        base_url="http://127.0.0.1",
        headers={"X-Totem-Request": "1"},
    ) as client:
        client.app.state.sessions.status = LogicalReadinessFixture()
        response = client.get("/local/context")
        assert response.status_code == 200 and "never-forward" not in response.text
        body = {"command_id": str(uuid4()), "class_id": str(CLASS), "mode": "student"}
        session = client.post("/local/sessions", json=body).json()
        path = f"/local/sessions/{session['event_id']}/pin"
        invalid = client.post(
            path, json={"student_id": str(STUDENT), "pin": "private-input"}
        )
        assert invalid.status_code == 422 and "private-input" not in invalid.text
        assert (
            client.post(path, json={"student_id": str(STUDENT), "pin": "0012"}).json()[
                "state"
            ]
            == "SAFETY"
        )
        assert (
            client.post(
                path, json={"student_id": str(STUDENT), "pin": "0012"}
            ).status_code
            == 409
        )
        assert client.get("/local/status").json()["can_start_deposit"] is False
        assert (
            client.post(
                f"/local/sessions/{session['event_id']}/finish", json={}
            ).status_code
            == 409
        )


@pytest.mark.parametrize(
    "headers", [{"Origin": "https://foreign.invalid", "X-Totem-Request": "1"}, {}]
)
def test_mutations_require_local_origin_and_custom_header(headers):
    with TestClient(create_app(), base_url="http://127.0.0.1") as client:
        assert (
            client.post("/local/sessions", json={}, headers=headers).status_code == 403
        )
        assert (
            client.get(
                "/local/sessions/active", headers={"Host": "foreign.invalid"}
            ).status_code
            == 403
        )


def test_frontend_is_served_without_file_selection_query():
    with TestClient(create_app(), base_url="http://127.0.0.1") as client:
        assert "operational.js" in client.get("/").text
        script = client.get("/script.js?name=../../backend/.env")
        assert script.status_code == 200 and "BinGoOperational" in script.text
        assert client.get("/README.md").status_code == 404
        assert client.get("/local/sessions/active?pin=private-input").status_code == 422


def seed_persisted_state(store, state, *, confirmed=False, scope=None):
    """Fixture SQLite de recuperação; não emite ou simula movimento físico."""
    session = store.create(uuid4(), "class_only", CLASS, "7 A", central_scope=scope)
    payload = DepositPayload(
        event_id=session.event_id,
        class_id=CLASS,
        student_id=None,
        is_valid=True,
        detected_type="cable",
        waste_category_code="CABLE_WIRE",
        category_source="AI_CONFIRMED",
    )
    with store.transaction() as conn:
        conn.execute(
            "UPDATE cycles SET state=?,physical_confirmed=?,payload=? WHERE event_id=?",
            (state, int(confirmed), payload.model_dump_json(), str(session.event_id)),
        )
    return session.event_id, payload


def test_hand_removed_route_records_only_declaration_and_remains_blocked():
    with TestClient(
        create_app(), base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        store = client.app.state.sessions.store
        event_id, _ = seed_persisted_state(store, "DOOR_OPEN")
        path = f"/local/sessions/{event_id}/hand-removed"
        assert client.post(path, json={}).status_code == 503
        assert store.get(event_id).hand_removed is True
        assert store.get(event_id).state == "DOOR_OPEN"
        assert client.post(path, json={}).status_code == 409
        assert (
            client.post(f"/local/sessions/{event_id}/cancel", json={}).status_code
            == 409
        )


@pytest.mark.parametrize(
    "state",
    [
        "OPENING",
        "CLOSING",
        "HATCH_IN_PROGRESS",
        "DOOR_OPEN",
        "CAPTURING",
        "RETURN_REQUIRED",
    ],
)
def test_restart_unknown_critical_states_blocks_new_cycle(tmp_path, state):
    path = tmp_path / "restart.sqlite3"
    store = CycleStore(path)
    event_id, _ = seed_persisted_state(store, state)
    store.close()
    recovered = CycleStore(path)
    try:
        assert recovered.get(event_id).state == "INDETERMINATE"
        with pytest.raises(CycleError):
            recovered.create(uuid4(), "class_only", CLASS, "7 A")
    finally:
        recovered.close()


@pytest.mark.parametrize("state", ["REGISTRATION_PENDING", "REGISTERING"])
def test_no_confirmation_never_becomes_completed(tmp_path, state):
    path = tmp_path / "unknown.sqlite3"
    store = CycleStore(path)
    event_id, _ = seed_persisted_state(store, state, confirmed=False)
    store.close()
    recovered = CycleStore(path)
    try:
        assert recovered.get(event_id).state == "INDETERMINATE"
        assert recovered.get(event_id).receipt is None
    finally:
        recovered.close()


@pytest.mark.anyio
async def test_completed_pending_retry_same_event_after_restart_without_duplicate_points(
    tmp_path, configured_environment
):
    calls = []
    ledger = {}

    def upstream(request):
        body = json.loads(request.content)
        calls.append(body)
        # Supabase mock: responde replay sem reaplicar sua própria fotografia.
        existed = body["event_id"] in ledger
        ledger.setdefault(body["event_id"], receipt(body))
        if len(calls) == 1:
            raise httpx.ReadTimeout(
                "response lost after central commit", request=request
            )
        return httpx.Response(200 if existed else 201, json=ledger[body["event_id"]])

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        path = tmp_path / "pending.sqlite3"
        store = CycleStore(path)
        event_id, payload = seed_persisted_state(
            store,
            "REGISTRATION_PENDING",
            confirmed=True,
            scope=central.configuration_scope,
        )
        service = SessionService(store, central, LogicalReadinessFixture())
        with pytest.raises(CentralError):
            await service.retry_registration(event_id)
        assert store.get(event_id).state == "REGISTRATION_PENDING"
        assert store.get(event_id).receipt is None
        with pytest.raises(CycleError):
            service.cancel(event_id)
        with pytest.raises(CycleError):
            service.finish(event_id)
        store.close()
        store = CycleStore(path)
        service = SessionService(store, central, LogicalReadinessFixture())
        try:
            result = await service.retry_registration(event_id)
            assert (
                result.state == "REGISTERED"
                and result.receipt.points_awarded_class == 1900
            )
            assert (
                await service.retry_registration(event_id)
            ).receipt == result.receipt
            assert len(ledger) == 1 and len(calls) == 2
            assert calls[0] == calls[1] == payload.model_dump(mode="json")
            assert store.active() is not None  # Só finish libera o slot.
            store.close()
            store = CycleStore(path)
            service = SessionService(store, central, LogicalReadinessFixture())
            assert store.get(event_id).receipt == result.receipt
            assert (
                await service.retry_registration(event_id)
            ).receipt == result.receipt
            assert len(calls) == 2
            assert service.finish(event_id).state == "COMPLETED"
            assert service.finish(event_id).event_id == event_id
        finally:
            store.close()


@pytest.mark.anyio
async def test_concurrent_registration_claims_only_once(
    tmp_path, configured_environment
):
    calls = []

    async def upstream(request):
        calls.append(json.loads(request.content))
        await asyncio.sleep(0.01)
        return httpx.Response(201, json=receipt(calls[-1]))

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        store = CycleStore(tmp_path / "concurrent.sqlite3")
        event_id, _ = seed_persisted_state(
            store,
            "REGISTRATION_PENDING",
            confirmed=True,
            scope=central.configuration_scope,
        )
        a = SessionService(store, central, LogicalReadinessFixture())
        b = SessionService(store, central, LogicalReadinessFixture())
        try:
            results = await asyncio.gather(
                a.retry_registration(event_id),
                b.retry_registration(event_id),
                return_exceptions=True,
            )
            assert len(calls) == 1
            assert sum(isinstance(x, CycleError) for x in results) == 1
            assert store.get(event_id).state == "REGISTERED"
        finally:
            store.close()


def test_store_single_instance_and_immutable_payload(tmp_path):
    path = tmp_path / "single.sqlite3"
    store = CycleStore(path)
    try:
        with pytest.raises(OSError):
            CycleStore(path)
        event_id, payload = seed_persisted_state(store, "REVIEW")
        store.prepare_payload(event_id, payload)
        with pytest.raises(CycleError):
            store.prepare_payload(
                event_id, payload.model_copy(update={"detected_type": "changed"})
            )
        with pytest.raises(CycleError):
            store.claim_registration(event_id, None)
    finally:
        store.close()


def test_restart_logical_session_keeps_id_and_cancels_preparation(tmp_path):
    path = tmp_path / "logical-restart.sqlite3"
    store = CycleStore(path)
    session = store.create(uuid4(), "student", CLASS, "7 A")
    store.close()
    recovered = CycleStore(path)
    try:
        assert recovered.get(session.event_id).state == "CANCELLED"
        assert recovered.active() is None
        with recovered.transaction() as conn:
            assert (
                conn.execute(
                    "SELECT count(*) FROM transitions WHERE event_id=?",
                    (str(session.event_id),),
                ).fetchone()[0]
                == 2
            )
    finally:
        recovered.close()


def test_incompatible_sqlite_is_not_erased_or_replaced(tmp_path):
    path = tmp_path / "incompatible.sqlite3"
    with sqlite3.connect(path) as conn:
        conn.execute("CREATE TABLE cycles(event_id TEXT PRIMARY KEY)")
        conn.execute("INSERT INTO cycles VALUES('must-preserve')")
        conn.execute("PRAGMA user_version=1")
    with pytest.raises(RuntimeError, match="bloqueada"):
        CycleStore(path)
    with sqlite3.connect(path) as conn:
        assert conn.execute("SELECT event_id FROM cycles").fetchall() == [
            ("must-preserve",)
        ]


@pytest.mark.anyio
async def test_scope_change_and_bad_receipt_keep_pending(
    tmp_path, configured_environment
):
    requests = []

    def upstream(request):
        requests.append(request)
        return httpx.Response(
            201, json={**receipt(json.loads(request.content)), "event_id": str(uuid4())}
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        store = CycleStore(tmp_path / "scope.sqlite3")
        event_id, _ = seed_persisted_state(
            store, "REGISTRATION_PENDING", confirmed=True, scope="other-environment"
        )
        service = SessionService(store, central, LogicalReadinessFixture())
        try:
            with pytest.raises(CycleError):
                await service.retry_registration(event_id)
            assert not requests
            with store.transaction() as conn:
                conn.execute(
                    "UPDATE cycles SET central_scope=?", (central.configuration_scope,)
                )
            with pytest.raises(CentralError):
                await service.retry_registration(event_id)
            assert store.get(event_id).state == "REGISTRATION_PENDING"
            assert store.get(event_id).receipt is None
        finally:
            store.close()
