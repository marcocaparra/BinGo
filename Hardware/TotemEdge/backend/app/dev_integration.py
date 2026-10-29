"""Perfil DEV: capacidades centrais estreitas, separadas da mecânica simulada."""

from dataclasses import dataclass
import json
import os
from pathlib import Path
from typing import Literal
from uuid import UUID

import httpx2 as httpx
from pydantic import BaseModel, ConfigDict, model_validator

from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.config import SupabaseSettings
from app.services.controller import DEFAULT_PLANS, SimulationPlan
from app.simulation import EXTERNAL_PREFIXES, PROXY_VARIABLES, SimulationSettings

# Referência DEV documentada em mobile-supabase-auth-profile.md. Não é segredo.
DEV_PROJECT = "ddxmohrjcxuibswmrtla"
DEV_URL = f"https://{DEV_PROJECT}.supabase.co"
DIRECTORY = Path("/var/lib/bingo-dev-integration")
POLICY_FILE = Path("/run/configs/dev-policy.json")
KEY_FILE = Path("/run/secrets/dev-machine-key")
BROKER = "http://dev-central:8000"
LOGICAL_ORIGIN = "http://127.0.0.1"
ALLOWED = frozenset(
    {
        ("GET", "/functions/v1/health-v1"),
        ("GET", "/functions/v1/totem-context-v1"),
        ("POST", "/functions/v1/totem-student-pin-v1"),
    }
)


class DevConfigurationError(RuntimeError):
    def __init__(self):
        super().__init__(
            "DEV_UNSAFE_CONFIGURATION: política, segredo ou ambiente inválido."
        )


class DevPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    project_ref: Literal["ddxmohrjcxuibswmrtla"]
    test_data_only: Literal[True]
    machine_id: UUID
    school_id: UUID
    class_ids: tuple[UUID, ...]
    student_ids: tuple[UUID, ...]

    @model_validator(mode="before")
    @classmethod
    def explicit_test_scope(cls, value):
        if not isinstance(value, dict) or value.get("test_data_only") is not True:
            raise ValueError("Escopo sintético obrigatório.")
        return value

    @model_validator(mode="after")
    def unique_scope(self):
        if (
            not self.class_ids
            or len(set(self.class_ids)) != len(self.class_ids)
            or len(set(self.student_ids)) != len(self.student_ids)
        ):
            raise ValueError("Escopo inválido.")
        return self


def read_file(path: Path) -> str:
    try:
        if (
            not path.is_absolute()
            or path.is_symlink()
            or not path.is_file()
            or path.stat().st_size > 65536
        ):
            raise DevConfigurationError()
        return path.read_text(encoding="utf-8")
    except (OSError, ValueError):
        raise DevConfigurationError() from None


def load_policy(path=POLICY_FILE):
    try:
        return DevPolicy.model_validate_json(read_file(path))
    except ValueError:
        raise DevConfigurationError() from None


def load_machine_key(path=KEY_FILE):
    value = read_file(path).removesuffix("\n").removesuffix("\r")
    if (
        not value
        or value.startswith(("eyJ", "sb_"))
        or value.count(".") == 2
        or not all(32 <= ord(c) < 127 for c in value)
    ):
        raise DevConfigurationError()
    return value


def validate_environment():
    if os.getenv("BINGO_DEV_CONTEXT") not in {"development", "test"}:
        raise DevConfigurationError()
    if any(name.startswith("BINGO_SIMULATION_") for name in os.environ):
        raise DevConfigurationError()
    if any(
        value and (name.startswith(EXTERNAL_PREFIXES) or name in PROXY_VARIABLES)
        for name, value in os.environ.items()
    ):
        raise DevConfigurationError()
    if any(
        name.startswith("BINGO_DEV_")
        and name not in {"BINGO_DEV_CONTEXT", "BINGO_DEV_PLANS"}
        for name in os.environ
    ):
        raise DevConfigurationError()


class FunctionTransport(httpx.AsyncBaseTransport):
    """Sem CONNECT, redirects, query, RPC ou encaminhamento de destino/headers livres."""

    def __init__(self, *, native=False, inner=None):
        self.native = native
        self.inner = (
            inner if inner is not None else httpx.AsyncHTTPTransport(trust_env=False)
        )

    async def handle_async_request(self, request):
        origin = DEV_URL if self.native else LOGICAL_ORIGIN
        path = request.url.path
        if (
            str(request.url) != origin + path
            or request.url.raw_path != path.encode("ascii")
            or (request.method, path) not in ALLOWED
        ):
            raise CentralError("DEV_CAPABILITY_DENIED", 403)
        headers = {"Accept": "application/json"}
        if self.native:
            headers.update(
                {name: request.headers[name] for name in ("X-Machine-Id", "X-Api-Key")}
            )
        else:
            headers["X-Totem-Dev"] = "1"
        if request.method == "POST":
            headers["Content-Type"] = "application/json"
        forwarded = httpx.Request(
            request.method,
            (DEV_URL if self.native else BROKER) + path,
            headers=headers,
            content=await request.aread(),
            extensions=request.extensions,
        )
        return await self.inner.handle_async_request(forwarded)

    async def aclose(self):
        await self.inner.aclose()


class DevCentralClient(SupabaseEdgeClient):
    def __init__(self, http_client, policy, *, machine_key=None):
        self.policy = policy
        super().__init__(
            http_client,
            settings=SupabaseSettings(
                base_url=DEV_URL if machine_key is not None else LOGICAL_ORIGIN,
                machine_id=str(policy.machine_id),
                machine_api_key=machine_key
                if machine_key is not None
                else "internal-read-only",
            ),
        )

    @property
    def configuration_scope(self):
        # Dados centrais não concedem elegibilidade econômica às sessões.
        return None

    async def register(self, payload):
        raise CentralError("DEV_CAPABILITY_DENIED", 403)

    async def context(self):
        context = await super().context()
        if (
            context.school.id != self.policy.school_id
            or any(c.id not in self.policy.class_ids for c in context.classes)
            or any(s.id not in self.policy.student_ids for s in context.students)
        ):
            raise CentralError("DEV_TEST_SCOPE_MISMATCH", 403)
        return context

    async def verify_pin(self, class_id, student_id, pin):
        if (
            class_id not in self.policy.class_ids
            or student_id not in self.policy.student_ids
        ):
            raise CentralError("DEV_TEST_SCOPE_MISMATCH", 403)
        context = await self.context()
        if not any(
            s.id == student_id and s.class_id == class_id for s in context.students
        ):
            raise CentralError("DEV_TEST_SCOPE_MISMATCH", 403)
        return await super().verify_pin(class_id, student_id, pin)


@dataclass(frozen=True)
class DevSettings(SimulationSettings):
    policy: DevPolicy

    dev_integration = True
    marker_name = ".bingo-dev-integration-only"
    marker_content = "BinGo TotemEdge DEV integration simulation only v1\n"

    def validate_environment(self):
        validate_environment()
        value = os.getenv("BINGO_SQLITE_PATH", "")
        if (
            not value
            or not Path(value).is_absolute()
            or Path(value).resolve() != self.sqlite_path
        ):
            raise DevConfigurationError()

    def build_transport(self, transport=None):
        return FunctionTransport(inner=transport)

    def build_central(self, http_client):
        return DevCentralClient(http_client, self.policy)


def create_dev_app(
    *, data_directory=DIRECTORY, policy_path=POLICY_FILE, transport=None
):
    from app.main import create_app

    validate_environment()
    try:
        plans = dict(DEFAULT_PLANS)
        overrides = json.loads(os.getenv("BINGO_DEV_PLANS", "{}"))
        if not isinstance(overrides, dict) or not overrides.keys() <= plans.keys():
            raise DevConfigurationError()
        plans.update(
            {
                name: SimulationPlan.model_validate(value)
                for name, value in overrides.items()
            }
        )
        settings = DevSettings(
            data_directory.resolve(), plans, load_policy(policy_path)
        )
        settings.validate_environment()
    except (ValueError, TypeError, OSError):
        raise DevConfigurationError() from None
    return create_app(
        transport=transport,
        controller_factory=settings.build_controller,
        _simulation=settings,
    )
