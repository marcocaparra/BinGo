"""Explicit opt-in entrypoint; never selected by the normal DEV runtime."""

from pathlib import Path
import start

if __name__ == "__main__":
    raise SystemExit(
        start.main(
            directory=Path("/var/lib/bingo-vision-lab"),
            application="app.vision_lab:create_vision_lab_app",
            factory=True,
        )
    )
