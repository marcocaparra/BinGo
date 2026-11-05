"""Explicit vision profiles: synthetic lab or existing read-only identity broker.

Both use simulated mechanics and have no economic registration capability.
"""

from dataclasses import dataclass, field
import json
import os
from pathlib import Path
from uuid import UUID

import httpx2 as httpx

from app.dev_integration import DevSettings, DevPolicy, DevConfigurationError, read_file
from app.dev_integration import FunctionTransport, load_policy, POLICY_FILE
from app.services.controller import DEFAULT_PLANS
from app.services.vision import (
    VisionSettings,
    InternalVision,
    RekognitionProvider,
    GeminiProvider,
)
from app.simulation import EXTERNAL_PREFIXES, PROXY_VARIABLES

DIRECTORY = Path("/var/lib/bingo-vision-lab")
MACHINE, SCHOOL, CLASS, STUDENT = [
    str(UUID(f"00000000-0000-4000-8000-{i:012d}")) for i in range(1, 5)
]


def synthetic_central(request):
    if request.method == "GET" and request.url.path.endswith("health-v1"):
        return httpx.Response(
            200,
            json=dict(
                status="AVAILABLE",
                can_start_deposit=True,
                scope="CENTRAL_BACKEND",
                checked_at="2026-11-01T00:00:00Z",
            ),
        )
    if request.method == "GET" and request.url.path.endswith("totem-context-v1"):
        return httpx.Response(
            200,
            json=dict(
                machine=dict(id=MACHINE, name="Laboratório de visão — simulado"),
                school=dict(id=SCHOOL, name="Escola fictícia"),
                classes=[
                    dict(
                        id=CLASS,
                        name="Turma fictícia",
                        segment="ENSINO_MEDIO",
                        grade="1",
                        points_class_balance=0,
                    )
                ],
                students=[
                    dict(
                        id=STUDENT,
                        class_id=CLASS,
                        class_name="Turma fictícia",
                        name="Aluno fictício",
                        status="ACTIVE",
                        points_student_balance=0,
                    )
                ],
            ),
        )
    if request.method == "POST" and request.url.path.endswith("totem-student-pin-v1"):
        body = json.loads(request.content)
        if body == dict(class_id=CLASS, student_id=STUDENT, pin="0012"):
            return httpx.Response(
                200,
                json=dict(
                    confirmed=True,
                    student=dict(
                        id=STUDENT,
                        class_id=CLASS,
                        class_name="Turma fictícia",
                        name="Aluno fictício",
                    ),
                ),
            )
        return httpx.Response(401, json={"error": {"code": "STUDENT_PIN_INVALID"}})
    # No path, including register-deposit-v1, can leave this in-memory broker.
    return httpx.Response(403, json={"error": {"code": "DEV_CAPABILITY_DENIED"}})


@dataclass(frozen=True)
class VisionLabSettings(DevSettings):
    vision_settings: VisionSettings = field(repr=False)
    vision_override: object = field(default=None, repr=False)
    deferred_analysis: bool = False
    vision_enabled = True
    marker_name = ".bingo-vision-lab-only"
    marker_content = "BinGo isolated vision lab synthetic mechanics v1\n"

    def validate_environment(self):
        if os.getenv("BINGO_VISION_LAB_CONTEXT") not in {"development", "test"}:
            raise DevConfigurationError()
        if any(
            value
            and (
                name.startswith(EXTERNAL_PREFIXES)
                or name.startswith(("BINGO_DEV_", "BINGO_SIMULATION_"))
                or name in PROXY_VARIABLES
            )
            for name, value in os.environ.items()
        ):
            raise DevConfigurationError()
        if Path(os.getenv("BINGO_SQLITE_PATH", "")).resolve() != self.sqlite_path:
            raise DevConfigurationError()

    def build_transport(self, transport=None):
        return httpx.MockTransport(synthetic_central)

    def build_vision(self, client):
        if self.vision_override is not None:
            return self.vision_override
        settings = self.vision_settings
        return InternalVision(
            RekognitionProvider(settings),
            GeminiProvider(client, settings) if settings.gemini_key else None,
        )


def create_vision_lab_app(
    *,
    data_directory=DIRECTORY,
    camera_transport=None,
    vision=None,
    deferred_analysis=False,
):
    from app.main import create_app

    try:
        path = os.getenv("BINGO_VISION_CREDENTIALS_FILE")
        settings = (
            VisionSettings(**json.loads(read_file(Path(path))))
            if path
            else VisionSettings()
        )
        lab = VisionLabSettings(
            data_directory.resolve(),
            dict(DEFAULT_PLANS),
            DevPolicy(
                project_ref="ddxmohrjcxuibswmrtla", machine_id=MACHINE, school_id=SCHOOL
            ),
            settings,
            vision,
            deferred_analysis,
        )
        lab.validate_environment()
    except Exception:
        raise DevConfigurationError() from None
    return create_app(
        _simulation=lab,
        controller_factory=lab.build_controller,
        camera_transport=camera_transport,
    )


@dataclass(frozen=True)
class VisionDevSettings(VisionLabSettings):
    doorless = True
    deferred_analysis: bool = False
    marker_name = ".bingo-vision-dev-only"
    marker_content = "BinGo vision DEV read-only identity simulated mechanics v1\n"

    def build_transport(self, transport=None):
        return FunctionTransport(
            inner=transport, economic_registration=self.policy.economic_registration
        )


def create_vision_dev_app(
    *,
    data_directory=Path("/var/lib/bingo-vision-dev"),
    policy_path=POLICY_FILE,
    transport=None,
    camera_transport=None,
    vision=None,
):
    """Reuse the existing read-only broker; no synthetic identity fallback."""
    from app.main import create_app

    try:
        path = os.getenv("BINGO_VISION_CREDENTIALS_FILE")
        settings = (
            VisionSettings(**json.loads(read_file(Path(path))))
            if path
            else VisionSettings()
        )
        profile = VisionDevSettings(
            data_directory.resolve(),
            dict(DEFAULT_PLANS),
            load_policy(policy_path),
            settings,
            vision,
        )
        profile.validate_environment()
    except Exception:
        raise DevConfigurationError() from None
    return create_app(
        _simulation=profile,
        controller_factory=profile.build_controller,
        transport=transport,
        camera_transport=camera_transport,
    )
