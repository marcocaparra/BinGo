"""Fixture controlada de journal/visão, sem créditos hospedados ou hardware."""

import json
from uuid import uuid4

import httpx2 as httpx
import pytest
from test_dev_integration import CLASS, CONTEXT, MACHINE, SCHOOL, STUDENT

from app.central_contracts import ConfirmedStudent
from app.cycles import CycleError, SimulationIdentity
from app.dev_integration import DEV_PROJECT, DevCentralClient, DevPolicy
from app.services.dev_economy import DevEconomy
from app.storage import CycleStore, now


@pytest.mark.anyio
async def test_dev_credit_retry_and_failure_guards(tmp_path):
    calls, ledger = [], {}

    def upstream(request):
        if request.method == "GET":
            return httpx.Response(200, json=CONTEXT)
        body = json.loads(request.content)
        calls.append(body)
        ledger.setdefault(
            body["event_id"],
            {
                "id": str(uuid4()),
                "event_id": body["event_id"],
                "waste_category_code": "UNKNOWN",
                "category_source": "UNIDENTIFIED",
                "bonus_rate_applied": 0,
                "bonus_bincoins_awarded": 0,
                "points_awarded_student": 800,
                "points_awarded_class": 1900,
                "created_at": now(),
            },
        )
        if len(calls) == 1:
            raise httpx.ReadTimeout("lost", request=request)
        return httpx.Response(200, json=ledger[body["event_id"]])

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        policy = DevPolicy(
            project_ref=DEV_PROJECT,
            machine_id=MACHINE,
            school_id=SCHOOL,
            economic_registration=True,
        )
        central = DevCentralClient(http, policy)
        store = CycleStore(
            tmp_path / "cycles.db",
            simulation_enabled=True,
            identity_scope=(DEV_PROJECT, MACHINE, SCHOOL),
        )
        try:
            econ = DevEconomy(store, central)
            event = store.create(
                uuid4(), "student", CLASS, "Turma", simulated=True
            ).event_id
            store.bind_simulation_identity(
                SimulationIdentity(
                    event_id=event,
                    project_ref=DEV_PROJECT,
                    machine_id=MACHINE,
                    school_id=SCHOOL,
                    class_id=CLASS,
                    student_id=STUDENT,
                    validated_at=now(),
                ),
                ConfirmedStudent(
                    id=STUDENT, name="Aluno", class_id=CLASS, class_name="Turma"
                ),
                0,
            )
            with store.transaction() as conn, pytest.raises(CycleError):
                econ.queue(conn, event)
            await econ.process()
            assert calls == []
            # Registros de teste explícitos, não representam equipamentos reais.
            with store.transaction() as conn:
                close = None
                for op in [
                    "OPEN_INSERTION_DOOR",
                    "CLOSE_INSERTION_DOOR",
                    "CYCLE_LOWER_HATCH",
                    "CONFIRM_INITIAL_STATE",
                ]:
                    cmd = str(uuid4())
                    close = cmd if op == "CLOSE_INSERTION_DOOR" else close
                    conn.execute(
                        "INSERT INTO mechanical_commands VALUES(?,?,?,10,'SIMULATED','COMPLETED','SUCCEEDED',NULL,NULL,0,?,?)",
                        (cmd, str(event), op, now(), now()),
                    )
                    stamp = conn.execute(
                        "SELECT updated_at FROM mechanical_commands WHERE mechanical_command_id=?",
                        (cmd,),
                    ).fetchone()[0]
                    conn.execute(
                        "INSERT INTO mechanical_history VALUES(?,0,'COMPLETED','SUCCEEDED',NULL,?)",
                        (cmd, stamp),
                    )
                conn.execute(
                    "INSERT INTO vision_attempts VALUES(?,?,?,'COMPLETED',?,?,?,NULL,?,?)",
                    (
                        str(uuid4()),
                        str(event),
                        close,
                        json.dumps({"status": "recognized"}),
                        json.dumps({"category": "UNKNOWN", "source": "UNIDENTIFIED"}),
                        json.dumps({"camera": "DEVICE", "inference": "PROVIDER"}),
                        now(),
                        now(),
                    ),
                )
                conn.execute(
                    "UPDATE cycles SET state='COMPLETED' WHERE event_id=?",
                    (str(event),),
                )
                econ.queue(conn, event)
                assert econ.snapshot(conn, event)["receipt"] is None
            await econ.process()
            with store.transaction() as conn:
                assert econ.snapshot(conn, event)["status"] == "PENDING"
            store.close()
            store = CycleStore(
                tmp_path / "cycles.db",
                simulation_enabled=True,
                identity_scope=(DEV_PROJECT, MACHINE, SCHOOL),
            )
            econ = DevEconomy(store, central)
            await econ.process()
            await econ.process()
            assert len(ledger) == 1 and calls[0] == calls[1]
            with store.transaction() as conn:
                result = econ.snapshot(conn, event)
                assert result["receipt"]["points_awarded_student"] == 800
                assert tuple(
                    conn.execute(
                        "SELECT simulated,physical_confirmed,payload,receipt FROM cycles"
                    ).fetchone()
                ) == (1, 0, None, None)
            econ.finish(event)
        finally:
            store.close()


def test_production_ref_and_default_policy_cannot_authorize():
    with pytest.raises(ValueError):
        DevPolicy(
            project_ref="production",
            machine_id=MACHINE,
            school_id=SCHOOL,
            economic_registration=True,
        )
    assert (
        DevPolicy(
            project_ref=DEV_PROJECT, machine_id=MACHINE, school_id=SCHOOL
        ).economic_registration
        is False
    )
