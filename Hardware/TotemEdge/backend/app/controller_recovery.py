"""Explicit offline maintenance: same-ID GET and append-only inspection, no SUBMIT."""

import argparse
import asyncio
from pathlib import Path
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.services.c_controller import CProcessController
from app.services.commissioning import protected_file
from app.services.controller_config import CControllerSettings
from app.services.mechanical import MechanicalService
from app.storage import CycleStore, now


class Inspection(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    mechanical_command_id: UUID
    inspector: str = Field(min_length=3, max_length=120)
    power_isolation_reference: str = Field(min_length=10, max_length=500)
    findings: str = Field(min_length=40, max_length=8000)
    disposition: Literal["RETAIN_BLOCKED"]


async def inspect(config, backend, identifier, report=None):
    # Must stop the runtime first. Its existing lease and the C journal lock
    # prevent parallel recovery processes. Starting this child sends no PWM.
    settings = CControllerSettings.from_file(
        protected_file(config), backend_journal=backend
    )
    protected_file(settings.executable)
    if "bingo-c-test" in settings.journal.resolve().parts or not (
        backend.is_file() and settings.journal.is_file()
    ):
        raise ValueError("Recovery requires both retained production journals")
    store = CycleStore(backend)
    service = None
    controller = None
    try:
        controller = await CProcessController._connect_joint(
            config, backend_journal=backend
        )
        service = MechanicalService(store, controller, source="PHYSICAL")
        entry = await service.reconcile(identifier)
        if report:
            protected_file(report)
            if report.stat().st_size > 16384:
                raise ValueError("Inspection report too large")
            observation = Inspection.model_validate_json(report.read_bytes())
            if observation.mechanical_command_id != identifier:
                raise ValueError("Inspection identity mismatch")
            with store.transaction() as conn:
                conn.execute("""CREATE TABLE IF NOT EXISTS mechanical_inspections (
                    id INTEGER PRIMARY KEY, mechanical_command_id TEXT NOT NULL REFERENCES mechanical_commands(mechanical_command_id),
                    report TEXT NOT NULL, at TEXT NOT NULL)""")
                for action in ("UPDATE", "DELETE"):
                    conn.execute(f"""CREATE TRIGGER IF NOT EXISTS inspection_no_{action.lower()} BEFORE {action} ON mechanical_inspections
                        BEGIN SELECT RAISE(ABORT,'Retained physical inspection'); END""")
                conn.execute(
                    "INSERT INTO mechanical_inspections(mechanical_command_id,report,at) VALUES(?,?,?)",
                    (str(identifier), observation.model_dump_json(), now()),
                )
        return entry.model_dump_json()
    finally:
        try:
            if service:
                await service.aclose()
            elif controller:
                await controller.aclose()
        finally:
            store.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--backend-journal", type=Path, required=True)
    parser.add_argument("--id", type=UUID, required=True)
    parser.add_argument("--inspection", type=Path)
    args = parser.parse_args()
    print(
        asyncio.run(
            inspect(args.config, args.backend_journal, args.id, args.inspection)
        )
    )


if __name__ == "__main__":
    main()
