"""Read-only C physical preparation report; exit 2 always means blocked."""

import argparse
import asyncio
import os
from pathlib import Path
import sys

from app.mechanical import ControllerError
from app.services.c_controller import CProcessController


async def preflight(executable: Path) -> int:
    try:
        report = await CProcessController.physical_preflight(executable)
    except ControllerError as exc:
        print(exc.code, file=sys.stderr)
        return 2
    print(report.model_dump_json(indent=2))
    # Receiving evidence is not physical readiness. No enable/override option.
    return 2


async def configured_preflight(config: Path, backend_journal: Path) -> int:
    _, readiness = await CProcessController.diagnose_operational(
        config, backend_journal=backend_journal
    )
    print(readiness.model_dump_json(indent=2))
    return 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--executable", type=Path)
    selection.add_argument("--config", type=Path)
    parser.add_argument(
        "--backend-journal",
        type=Path,
        default=Path(
            os.getenv(
                "BINGO_SQLITE_PATH",
                str(Path(__file__).resolve().parents[1] / ".data/totem.sqlite3"),
            )
        ),
    )
    args = parser.parse_args()
    if args.config is not None:
        return asyncio.run(configured_preflight(args.config, args.backend_journal))
    return asyncio.run(preflight(args.executable))


if __name__ == "__main__":
    raise SystemExit(main())
