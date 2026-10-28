"""CLI privado: executar com o servidor parado, no volume exclusivo de simulação."""

import argparse
import asyncio
import json
import os
import sqlite3
import time
from uuid import UUID, uuid4

from app.cycles import CycleError
from app.mechanical import ControllerError, MechanicalCommand
from app.services.controller import DEFAULT_PLANS
from app.simulation import (
    SimulationConfigurationError,
    SimulationSettings,
    create_simulation_app,
)


def parser():
    value = argparse.ArgumentParser(description=__doc__)
    commands = value.add_subparsers(dest="action", required=True)
    commands.add_parser("config")
    run = commands.add_parser("run")
    run.add_argument("operation", choices=tuple(DEFAULT_PLANS))
    run.add_argument("--id", type=UUID, default=None)
    run.add_argument("--timeout", type=float, default=10.0)
    run.add_argument("--interrupt-after-accept", action="store_true")
    for name in ("show", "replay"):
        commands.add_parser(name).add_argument("id", type=UUID)
    return value


async def execute(args, *, data_directory=None):
    options = {} if data_directory is None else {"data_directory": data_directory}
    settings = SimulationSettings.from_environment(**options)
    if args.action == "config":
        return {
            "context": "development/test",
            "controller": type(settings.build_controller()).__name__,
            "central": "BLOCKED",
            "sqlite_path": str(settings.sqlite_path),
            "plans": {name: plan.model_dump() for name, plan in settings.plans.items()},
        }
    application = create_simulation_app(**options)
    async with application.router.lifespan_context(application):
        service = application.state.mechanical
        store = application.state.sessions.store
        if args.action == "show":
            return {
                "command": service.get(args.id).model_dump(mode="json"),
                "history": [
                    event.model_dump() for event in store.mechanical.history(args.id)
                ],
            }
        if args.action == "replay":
            entry = await service.submit(service.get(args.id).command)
            return {"result": entry.model_dump(mode="json")}
        previous = None
        if args.id is not None:
            try:
                previous = service.get(args.id)
            except ControllerError as error:
                if error.code != "MECHANICAL_COMMAND_NOT_FOUND":
                    raise
        if previous is not None:
            event_id = previous.command.event_id
        else:
            session = store.active()
            if session is None:
                # Fixture lógica explícita; não usa prontidão/contexto/PIN reais.
                session = store.create(
                    uuid4(),
                    "class_only",
                    UUID("00000000-0000-4000-8000-000000000010"),
                    "Simulação isolada",
                )
                session = store.change(session.event_id, "SAFETY", "PHYSICAL_BLOCKED")
            if session.state != "PHYSICAL_BLOCKED":
                raise ControllerError("MECHANICAL_CYCLE_NOT_BLOCKED")
            event_id = session.event_id
        request = MechanicalCommand(
            mechanical_command_id=args.id or uuid4(),
            event_id=event_id,
            operation=args.operation,
            timeout_seconds=args.timeout,
        )
        started = time.monotonic()
        entry = await service.submit(request)
        if args.interrupt_after_accept:
            if entry.phase != "ACCEPTED":
                raise ControllerError("MECHANICAL_COMMAND_NOT_ACCEPTED")
            print(
                json.dumps(
                    {"interrupted_after_acceptance": entry.model_dump(mode="json")}
                ),
                flush=True,
            )
            # Falha deliberada somente neste harness isolado; WAL/journal duráveis.
            os._exit(0)
        final = await service.wait(request.mechanical_command_id)
        return {
            "accepted": entry.model_dump(mode="json"),
            "result": final.model_dump(mode="json"),
            "elapsed_seconds": time.monotonic() - started,
        }


def main():
    args = parser().parse_args()
    os.umask(0o077)
    try:
        print(json.dumps(asyncio.run(execute(args))))
        return 0
    except (
        SimulationConfigurationError,
        ControllerError,
        CycleError,
        ValueError,
        OSError,
        sqlite3.Error,
    ) as error:
        code = getattr(
            error,
            "code",
            "SIMULATION_UNSAFE_CONFIGURATION"
            if isinstance(error, SimulationConfigurationError)
            else "SIMULATION_HARNESS_FAILED",
        )
        print(json.dumps({"error": {"code": code}}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
