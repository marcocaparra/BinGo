"""Deployment guards only; application behavior has its existing test suite."""

import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).parents[1] / f"{name}.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


start = load("start")
healthcheck = load("healthcheck")


class RuntimeTests(unittest.TestCase):
    def test_database_stays_in_persistent_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "nested" / "totem.sqlite3"
            self.assertEqual(
                start.persistent_sqlite_path(str(path), root), path.resolve()
            )
            for invalid in (
                "relative.sqlite3",
                str(root),
                str(root / ".." / "outside.sqlite3"),
            ):
                with self.subTest(path=invalid), self.assertRaises(ValueError):
                    start.persistent_sqlite_path(invalid, root)

    def test_symlink_cannot_escape_volume(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            persistent = root / "volume"
            persistent.mkdir()
            link = persistent / "escape"
            try:
                link.symlink_to(root, target_is_directory=True)
            except OSError:
                self.skipTest(
                    "Creating symlinks requires privileges on this host; also run in Linux container."
                )
            with self.assertRaises(ValueError):
                start.persistent_sqlite_path(str(link / "totem.sqlite3"), persistent)

    def test_missing_mount_does_not_start_uvicorn(self):
        with (
            patch.dict(
                os.environ, {"BINGO_SQLITE_PATH": "/var/lib/bingo/totem.sqlite3"}
            ),
            patch.object(
                start,
                "persistent_sqlite_path",
                return_value=Path("/var/lib/bingo/totem.sqlite3"),
            ),
            patch.object(start.os.path, "ismount", return_value=False),
            patch.object(start.os, "execv") as execute,
            patch("sys.stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(start.main(), 1)
            execute.assert_not_called()

    def test_launcher_replaces_itself_with_one_worker(self):
        with (
            patch.dict(
                os.environ, {"BINGO_SQLITE_PATH": "/var/lib/bingo/totem.sqlite3"}
            ),
            patch.object(
                start,
                "persistent_sqlite_path",
                return_value=Path("/var/lib/bingo/totem.sqlite3"),
            ),
            patch.object(start.os.path, "ismount", return_value=True),
            patch.object(start.os, "umask"),
            patch.object(start.os, "execv") as execute,
        ):
            start.main()
            arguments = execute.call_args.args[1]
            self.assertEqual(arguments[arguments.index("--workers") + 1], "1")
            self.assertNotIn("--reload", arguments)
            self.assertIn("--no-access-log", arguments)
            self.assertIn("--no-proxy-headers", arguments)

    def test_simulation_launcher_uses_explicit_factory_and_separate_mount(self):
        root = Path("/var/lib/bingo-simulation")
        with (
            patch.dict(
                os.environ, {"BINGO_SQLITE_PATH": str(root / "simulation.sqlite3")}
            ),
            patch.object(
                start,
                "persistent_sqlite_path",
                return_value=root / "simulation.sqlite3",
            ) as validate,
            patch.object(start.os.path, "ismount", return_value=True) as mounted,
            patch.object(start.os, "umask"),
            patch.object(start.os, "execv") as execute,
        ):
            start.main(
                directory=root,
                application="app.simulation:create_simulation_app",
                factory=True,
            )
            validate.assert_called_once_with(str(root / "simulation.sqlite3"), root)
            mounted.assert_called_once_with(root)
            arguments = execute.call_args.args[1]
            self.assertIn("app.simulation:create_simulation_app", arguments)
            self.assertIn("--factory", arguments)
            self.assertNotIn("app.main:app", arguments)

    def test_healthcheck_only_accepts_local_liveness(self):
        for status, body, expected in (
            (200, b'{"status":"ok"}', True),
            (200, b'{"status":"OFFLINE"}', False),
            (503, b'{"status":"ok"}', False),
            (200, b"not json", False),
        ):
            with (
                self.subTest(status=status, body=body),
                patch.object(healthcheck, "build_opener") as build,
            ):
                response = build.return_value.open.return_value.__enter__.return_value
                response.status = status
                response.read.return_value = body
                self.assertEqual(healthcheck.healthy(), expected)
                build.return_value.open.assert_called_once_with(
                    "http://127.0.0.1:8000/health", timeout=2
                )

    def test_healthcheck_fails_on_connection_error(self):
        with patch.object(healthcheck, "build_opener") as build:
            build.return_value.open.side_effect = OSError("connection unavailable")
            self.assertFalse(healthcheck.healthy())


if __name__ == "__main__":
    unittest.main()
