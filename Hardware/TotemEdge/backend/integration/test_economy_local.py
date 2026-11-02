"""Opt-in: cliente TotemEdge → handler HTTP Deno oficial → Supabase local.

Executar via deploy/check_economy_local.py. Não usa hardware, câmera ou IA.
As linhas econômicas de teste ficam no banco LOCAL para inspeção/auditoria.
"""

import asyncio
import json
import os
import subprocess
from uuid import UUID, uuid4

import httpx2 as httpx
import pytest
from app.central_contracts import DepositPayload
from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.config import SupabaseSettings
from app.services.sessions import SessionService
from app.storage import CycleStore

CLASS = UUID("20000000-0000-4000-8000-000000000001")
STUDENT = UUID("30000000-0000-4000-8000-000000000001")
MACHINE = "40000000-0000-4000-8000-000000000001"
pytestmark = pytest.mark.skipif(
    not os.getenv("TOTEM_TEST_EDGE_PORT"), reason="Usar o runner local explícito"
)


def query(sql):
    result = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            "supabase_db_Software",
            "psql",
            "-X",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-At",
        ],
        input=sql,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def snapshot(event):
    # Somente UUIDs gerados/constantes do teste, nunca entrada HTTP nesta consulta.
    return query(f"""select json_build_object(
        'student', (select points_student_balance from students where id='{STUDENT}'),
        'class', (select points_class_balance from classes where id='{CLASS}'),
        'deposits', (select count(*) from deposits where event_id='{event}'),
        'audits', (select count(*) from audit_logs where metadata->>'event_id'='{event}'),
        'audit', (select row_to_json(a) from audit_logs a where metadata->>'event_id'='{event}'),
        'machine_school', (select school_id from machines where id='{MACHINE}'),
        'history', (select row_to_json(d) from deposits d where event_id='{event}')
    );""")


def settings():
    port = int(os.environ["TOTEM_TEST_EDGE_PORT"])
    assert 0 < port < 65536
    return SupabaseSettings(f"http://127.0.0.1:{port}", MACHINE, "edge-demo-key", 15)


def payload(event=None, **changes):
    return DepositPayload.model_validate(
        {
            "event_id": event or uuid4(),
            "class_id": CLASS,
            "student_id": STUDENT,
            "is_valid": True,
            "detected_type": "CONTROLLED_LOCAL_ECONOMY_TEST",
            "waste_category_code": "BATTERY",
            "category_source": "AI_CONFIRMED",
            **changes,
        }
    )


def test_valid_anonymous_invalid_replay_conflict_concurrency():
    async def exercise():
        async with httpx.AsyncClient(trust_env=False) as http:
            central = SupabaseEdgeClient(http, settings=settings())
            for change in (
                {},
                {"student_id": None},
                {
                    "is_valid": False,
                    "waste_category_code": None,
                    "category_source": None,
                },
            ):
                body = payload(**change)
                before = snapshot(body.event_id)
                result = await central.register(body)
                after = snapshot(body.event_id)
                assert after["deposits"] == after["audits"] == 1
                assert (
                    after["student"] - before["student"]
                    == result.points_awarded_student
                )
                assert after["class"] - before["class"] == result.points_awarded_class
                assert (
                    after["history"]["points_awarded_student"]
                    == result.points_awarded_student
                )
                assert (
                    after["history"]["points_awarded_class"]
                    == result.points_awarded_class
                )
                assert str(result.id) == after["history"]["id"]
                assert after["history"]["machine_id"] == MACHINE
                assert after["history"]["school_id"] == after["machine_school"]
                assert after["audit"]["school_id"] == after["machine_school"]
                assert after["audit"]["actor_type"] == "MACHINE"
                assert after["audit"]["actor_id"] == MACHINE
                assert after["audit"]["action"] == "DEPOSIT_REGISTERED"
                assert (
                    after["history"]["bonus_bincoins_awarded"]
                    == result.bonus_bincoins_awarded
                )
                assert after["history"]["is_valid"] is body.is_valid
                if body.student_id is None:
                    assert (
                        result.points_awarded_student
                        == result.bonus_bincoins_awarded
                        == 0
                    )
                if not body.is_valid:
                    assert (
                        result.points_awarded_student
                        == result.points_awarded_class
                        == 0
                    )
                assert await central.register(body) == result
                assert snapshot(body.event_id) == after
                with pytest.raises(CentralError) as conflict:
                    await central.register(
                        body.model_copy(
                            update={"detected_type": "DIVERGENT_LOCAL_TEST"}
                        )
                    )
                assert conflict.value.code == "EVENT_ID_CONFLICT"
                assert snapshot(body.event_id) == after

            body = payload()
            before = snapshot(body.event_id)
            a, b = await asyncio.gather(central.register(body), central.register(body))
            assert a == b
            after = snapshot(body.event_id)
            assert after["deposits"] == after["audits"] == 1
            assert after["student"] - before["student"] == a.points_awarded_student
            assert after["class"] - before["class"] == a.points_awarded_class

    asyncio.run(exercise())


def test_real_commit_lost_response_restart_and_local_history(tmp_path):
    async def exercise():
        calls = []
        async with httpx.AsyncClient(trust_env=False) as live:

            async def lose_first_response(request):
                # O handler/RPC faz commit real LOCAL antes da perda controlada.
                response = await live.send(request)
                calls.append(json.loads(request.content))
                if len(calls) == 1:
                    raise httpx.ReadTimeout("controlled lost response", request=request)
                return response

            async with httpx.AsyncClient(
                transport=httpx.MockTransport(lose_first_response), trust_env=False
            ) as http:
                central = SupabaseEdgeClient(http, settings=settings())
                path = tmp_path / "outbox.sqlite3"
                store = CycleStore(path)
                session = store.create(
                    uuid4(),
                    "student",
                    CLASS,
                    "Turma DEV",
                    central_scope=central.configuration_scope,
                )
                body = payload(session.event_id)
                # Fixture isolada do handoff autorizado; não é prova de hardware.
                with store.transaction() as conn:
                    conn.execute(
                        "UPDATE cycles SET state='REVIEW',student_id=? WHERE event_id=?",
                        (str(STUDENT), str(session.event_id)),
                    )
                store.prepare_payload(session.event_id, body)
                assert store.get(session.event_id).receipt is None
                before = snapshot(session.event_id)
                assert before["deposits"] == 0
                with store.transaction() as conn:
                    conn.execute(
                        "UPDATE cycles SET state='HATCH_IN_PROGRESS',physical_confirmed=1 WHERE event_id=?",
                        (str(session.event_id),),
                    )
                service = SessionService(store, central, None)
                with pytest.raises(CentralError):
                    await service.register_completed(session.event_id)
                assert store.get(session.event_id).state == "REGISTRATION_PENDING"
                assert store.get(session.event_id).receipt is None
                committed = snapshot(session.event_id)
                assert committed["deposits"] == committed["audits"] == 1
                store.close()
                store = CycleStore(path)
                try:
                    service = SessionService(store, central, None)
                    confirmed = await service.retry_registration(session.event_id)
                    assert confirmed.state == "REGISTERED"
                    assert calls == [body.model_dump(mode="json")] * 2
                    assert snapshot(session.event_id) == committed
                    assert (
                        committed["student"] - before["student"]
                        == confirmed.receipt.points_awarded_student
                    )
                    assert (
                        committed["class"] - before["class"]
                        == confirmed.receipt.points_awarded_class
                    )
                    with store.transaction() as conn:
                        history = [
                            r[0]
                            for r in conn.execute(
                                "SELECT to_state FROM transitions ORDER BY id"
                            )
                        ]
                    assert history[-4:] == [
                        "REGISTERING",
                        "REGISTRATION_PENDING",
                        "REGISTERING",
                        "REGISTERED",
                    ]
                    service.finish(session.event_id)
                finally:
                    store.close()

    asyncio.run(exercise())
