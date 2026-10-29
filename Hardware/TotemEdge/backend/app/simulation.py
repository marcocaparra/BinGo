"""Composição exclusiva de desenvolvimento: sem clientes/credenciais externos."""

from dataclasses import dataclass
from contextlib import closing
import json
import logging
import os
from pathlib import Path
import sqlite3

import httpx2 as httpx

from app.clients.supabase import CentralError, CentralReadiness
from app.services.controller import DEFAULT_PLANS, SimulatedController, SimulationPlan

SIMULATION_DIRECTORY = Path("/var/lib/bingo-simulation")
DATABASE_NAME = "simulation.sqlite3"
MARKER = ".bingo-simulation-only"
MARKER_CONTENT = "BinGo TotemEdge isolated simulation v1\n"
EXTERNAL_PREFIXES = (
    "BINGO_SUPABASE_",
    "BINGO_MACHINE_",
    "SUPABASE_",
    "AWS_",
    "GEMINI_",
    "BINGO_GEMINI_",
)
PROXY_VARIABLES = (
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
)


class SimulationConfigurationError(RuntimeError):
    def __init__(self):
        super().__init__(
            "SIMULATION_UNSAFE_CONFIGURATION: ambiente ou dados incompatíveis."
        )


def reject_simulation_in_operational(sqlite_path: Path):
    if any(name.startswith(("BINGO_SIMULATION_", "BINGO_DEV_")) for name in os.environ):
        raise SimulationConfigurationError()
    if any(
        (parent / marker).exists()
        for parent in sqlite_path.resolve().parents
        for marker in (MARKER, ".bingo-dev-integration-only")
    ):
        raise SimulationConfigurationError()


class BlockedCentralClient:
    """Sem HTTP, configuração ou destino; nenhuma operação econômica disponível."""

    configuration_scope = None

    async def check_health(self) -> CentralReadiness:
        return CentralReadiness("UNAVAILABLE")

    async def context(self):
        raise CentralError("SIMULATION_CENTRAL_DISABLED")

    async def verify_pin(self, class_id, student_id, pin):
        raise CentralError("SIMULATION_CENTRAL_DISABLED")

    async def register(self, payload):
        raise CentralError("SIMULATION_CENTRAL_DISABLED")


class DenyExternalTransport(httpx.AsyncBaseTransport):
    async def handle_async_request(self, request):
        raise CentralError("SIMULATION_NETWORK_DISABLED")


@dataclass(frozen=True)
class SimulationSettings:
    directory: Path
    plans: dict[str, SimulationPlan]

    marker_name = MARKER
    marker_content = MARKER_CONTENT

    def build_transport(self, transport=None):
        return DenyExternalTransport()

    def build_central(self, http_client):
        return BlockedCentralClient()

    @property
    def sqlite_path(self) -> Path:
        return self.directory / DATABASE_NAME

    def validate_environment(self):
        if any(name.startswith("BINGO_DEV_") for name in os.environ):
            raise SimulationConfigurationError()
        if os.getenv("BINGO_SIMULATION_CONTEXT") not in {"development", "test"}:
            raise SimulationConfigurationError()
        if any(
            value and name.startswith(EXTERNAL_PREFIXES)
            for name, value in os.environ.items()
        ):
            raise SimulationConfigurationError()
        if any(os.getenv(name) for name in PROXY_VARIABLES):
            raise SimulationConfigurationError()
        if any(
            name.startswith("BINGO_SIMULATION_")
            and name not in {"BINGO_SIMULATION_CONTEXT", "BINGO_SIMULATION_PLANS"}
            for name in os.environ
        ):
            raise SimulationConfigurationError()
        value = os.getenv("BINGO_SQLITE_PATH", "")
        if (
            not value
            or not Path(value).is_absolute()
            or Path(value).resolve() != self.sqlite_path
        ):
            raise SimulationConfigurationError()

    @classmethod
    def from_environment(cls, *, data_directory: Path = SIMULATION_DIRECTORY):
        try:
            plans = dict(DEFAULT_PLANS)
            overrides = json.loads(os.getenv("BINGO_SIMULATION_PLANS", "{}"))
            if not isinstance(overrides, dict) or not overrides.keys() <= plans.keys():
                raise ValueError()
            for operation, value in overrides.items():
                plans[operation] = SimulationPlan.model_validate(value)
            settings = cls(data_directory.resolve(), plans)
            settings.validate_environment()
            return settings
        except (ValueError, TypeError, OSError):
            raise SimulationConfigurationError() from None

    def build_controller(self):
        return SimulatedController(context="development", plans=self.plans)

    def prepare_storage(self):
        self.validate_environment()
        self.directory.mkdir(parents=True, exist_ok=True)
        allowed = {
            self.marker_name,
            DATABASE_NAME,
            DATABASE_NAME + "-wal",
            DATABASE_NAME + "-shm",
            DATABASE_NAME + ".lock",
        }
        files = list(self.directory.iterdir())
        if any(
            path.name not in allowed or path.is_symlink() or not path.is_file()
            for path in files
        ):
            raise SimulationConfigurationError()
        marker = self.directory / self.marker_name
        if not marker.exists():
            if files:
                raise SimulationConfigurationError()
            # Nunca adotar automaticamente um volume/banco já existente.
            with marker.open("x", encoding="utf-8") as stream:
                stream.write(self.marker_content)
                stream.flush()
                os.fsync(stream.fileno())
        if marker.read_text(encoding="utf-8") != self.marker_content:
            raise SimulationConfigurationError()
        if self.sqlite_path.exists():
            try:
                with closing(
                    sqlite3.connect(self.sqlite_path.as_uri() + "?mode=ro", uri=True)
                ) as conn:
                    conn.execute("PRAGMA query_only=ON")
                    if conn.execute(
                        "SELECT 1 FROM cycles WHERE physical_confirmed<>0 OR central_scope IS NOT NULL OR payload IS NOT NULL OR receipt IS NOT NULL LIMIT 1"
                    ).fetchone():
                        raise SimulationConfigurationError()
                    if conn.execute(
                        "SELECT 1 FROM mechanical_commands WHERE source='PHYSICAL' LIMIT 1"
                    ).fetchone():
                        raise SimulationConfigurationError()
            except sqlite3.Error:
                raise SimulationConfigurationError() from None


def create_simulation_app(*, data_directory: Path = SIMULATION_DIRECTORY):
    from app.main import create_app

    settings = SimulationSettings.from_environment(data_directory=data_directory)
    application = create_app(
        controller_factory=settings.build_controller, _simulation=settings
    )
    logging.getLogger("uvicorn.error").info(
        "SIMULATION ONLY: controller=SimulatedController central=blocked sqlite=%s",
        settings.sqlite_path,
    )
    return application
