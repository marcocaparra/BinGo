"""Opt-in vision with the existing read-only DEV identity broker."""

from pathlib import Path
import start

if __name__ == "__main__":
    raise SystemExit(
        start.main(
            directory=Path("/var/lib/bingo-vision-dev"),
            application="app.vision_lab:create_vision_dev_app",
            factory=True,
        )
    )
