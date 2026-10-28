"""Container-only configuration guard; does not change application recovery."""

import os
from pathlib import Path
import sys

DATA_DIRECTORY = Path("/var/lib/bingo")


def persistent_sqlite_path(value: str, directory: Path = DATA_DIRECTORY) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise ValueError("BINGO_SQLITE_PATH deve ser absoluto no container.")
    path = path.resolve()
    directory = directory.resolve()
    if path == directory or not path.is_relative_to(directory):
        raise ValueError(
            "BINGO_SQLITE_PATH deve estar no diretório persistente configurado."
        )
    return path


def main(*, directory=DATA_DIRECTORY, application="app.main:app", factory=False):
    try:
        path = persistent_sqlite_path(
            os.environ.get("BINGO_SQLITE_PATH", ""), directory
        )
        if not os.path.ismount(directory):
            raise ValueError("Volume persistente obrigatório no diretório configurado.")
    except (ValueError, OSError, RuntimeError) as error:
        # Messages describe configuration only, never the supplied value/secrets.
        print(
            str(error) if isinstance(error, ValueError) else "Caminho SQLite inválido.",
            file=sys.stderr,
        )
        return 1
    os.environ["BINGO_SQLITE_PATH"] = str(path)
    os.umask(0o077)
    os.execv(
        sys.executable,
        [
            sys.executable,
            "-m",
            "uvicorn",
            application,
            *(["--factory"] if factory else []),
            "--host",
            "0.0.0.0",
            "--port",
            "8000",
            "--workers",
            "1",
            "--no-access-log",
            "--no-proxy-headers",
            "--timeout-graceful-shutdown",
            "20",
        ],
    )


if __name__ == "__main__":
    raise SystemExit(main())
