"""Entrada explícita de desenvolvimento; nunca selecionada pelo start operacional."""

from pathlib import Path

import start


if __name__ == "__main__":
    raise SystemExit(
        start.main(
            directory=Path("/var/lib/bingo-simulation"),
            application="app.simulation:create_simulation_app",
            factory=True,
        )
    )
