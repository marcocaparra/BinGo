"""Fronteira econômica com SQLite temporário e transporte controlado.

As fixtures de evidência NÃO representam hardware ou descartes reais.
"""

import asyncio
import json
from uuid import uuid4

import httpx2 as httpx
import pytest
from app.central_contracts import DepositPayload
from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import CycleError
from app.services.sessions import SessionService
from app.storage import CycleStore
from test_sessions import CLASS, LogicalReadinessFixture, receipt, seed_persisted_state


@pytest.mark.anyio
async def test_handoff_commits_queue_before_io_and_replays_after_lost_response(
    tmp_path, configured_environment
):
    path = tmp_path / "economic.sqlite3"
    store = CycleStore(path)
    requests, ledger = [], {}

    def upstream(request):
        body = json.loads(request.content)
        requests.append(body)
        assert store.active().state == "REGISTERING"
        assert store.active().receipt is None
        with store.transaction() as conn:
            assert (
                conn.execute(
                    "SELECT count(*) FROM transitions WHERE code='ECONOMIC_REGISTRATION_QUEUED'"
                ).fetchone()[0]
                == 1
            )
        ledger.setdefault(body["event_id"], receipt(body))
        if len(requests) == 1:
            raise httpx.ReadTimeout("lost response", request=request)
        return httpx.Response(200, json=ledger[body["event_id"]])

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        event, payload = seed_persisted_state(
            store,
            "HATCH_IN_PROGRESS",
            confirmed=True,
            scope=central.configuration_scope,
        )
        service = SessionService(store, central, LogicalReadinessFixture())
        with pytest.raises(CentralError):
            await service.register_completed(event)
        assert store.get(event).state == "REGISTRATION_PENDING"
        assert store.get(event).receipt is None
        store.close()
        store = CycleStore(path)
        try:
            service = SessionService(store, central, LogicalReadinessFixture())
            result = await service.register_completed(event)
            assert result.state == "REGISTERED"
            assert result.receipt.points_awarded_class == 1900
            assert await service.register_completed(event) == result
            assert len(ledger) == 1
            assert requests == [payload.model_dump(mode="json")] * 2
        finally:
            store.close()


@pytest.mark.parametrize("confirmed", [False, True])
def test_restart_handoff_never_infers_physical_confirmation(tmp_path, confirmed):
    path = tmp_path / "restart.sqlite3"
    store = CycleStore(path)
    event, _ = seed_persisted_state(
        store, "HATCH_IN_PROGRESS", confirmed=confirmed, scope="fixture"
    )
    store.close()
    store = CycleStore(path)
    try:
        assert store.get(event).state == (
            "REGISTRATION_PENDING" if confirmed else "INDETERMINATE"
        )
        assert store.get(event).receipt is None
    finally:
        store.close()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "case", ["unconfirmed", "simulation", "scope", "wrong_state", "missing_payload"]
)
async def test_ineligible_handoff_never_calls_central(
    tmp_path, configured_environment, case
):
    calls = []
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda r: calls.append(r))
    ) as http:
        central = SupabaseEdgeClient(http)
        store = CycleStore(
            tmp_path / "blocked.sqlite3", simulation_enabled=case == "simulation"
        )
        try:
            if case == "simulation":
                event = store.create(
                    uuid4(), "class_only", CLASS, "Turma", simulated=True
                ).event_id
                forged = DepositPayload(
                    event_id=event,
                    class_id=CLASS,
                    student_id=None,
                    is_valid=True,
                    detected_type=None,
                    waste_category_code="UNKNOWN",
                    category_source="UNIDENTIFIED",
                )
                with store.transaction() as conn:
                    conn.execute(
                        "UPDATE cycles SET state='HATCH_IN_PROGRESS',physical_confirmed=1,payload=?,central_scope=?",
                        (forged.model_dump_json(), central.configuration_scope),
                    )
            else:
                event, _ = seed_persisted_state(
                    store,
                    "REVIEW" if case == "wrong_state" else "HATCH_IN_PROGRESS",
                    confirmed=case != "unconfirmed",
                    scope="different"
                    if case == "scope"
                    else central.configuration_scope,
                )
                if case == "missing_payload":
                    with store.transaction() as conn:
                        conn.execute("UPDATE cycles SET payload=NULL")
            service = SessionService(store, central, LogicalReadinessFixture())
            with pytest.raises(CycleError) as error:
                await service.register_completed(event)
            if case == "simulation":
                assert error.value.code == "SIMULATION_NOT_ECONOMICALLY_ELIGIBLE"
            assert not calls and store.get(event).receipt is None
        finally:
            store.close()


@pytest.mark.anyio
async def test_cancelled_http_preserves_pending_without_receipt(
    tmp_path, configured_environment
):
    async def upstream(request):
        raise asyncio.CancelledError()

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        central = SupabaseEdgeClient(http)
        store = CycleStore(tmp_path / "cancel.sqlite3")
        try:
            event, _ = seed_persisted_state(
                store,
                "HATCH_IN_PROGRESS",
                confirmed=True,
                scope=central.configuration_scope,
            )
            service = SessionService(store, central, LogicalReadinessFixture())
            with pytest.raises(asyncio.CancelledError):
                await service.register_completed(event)
            assert store.get(event).state == "REGISTRATION_PENDING"
            assert store.get(event).receipt is None
        finally:
            store.close()
