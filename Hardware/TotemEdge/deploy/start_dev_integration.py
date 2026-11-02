"""Entrada DEV explícita; reaproveita validação de volume e processo único."""

from pathlib import Path

import start


if __name__ == "__main__":
    raise SystemExit(
        start.main(
            directory=Path("/var/lib/bingo-dev-integration"),
            application="app.dev_integration:create_dev_app",
            factory=True,
        )
    )
