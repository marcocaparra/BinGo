"""Ponto interno de câmera/visão; sem driver, provedor ou rota de captura."""

import asyncio
from dataclasses import dataclass
from typing import Literal, Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.cycles import CycleError
from app.storage import CycleStore


@dataclass(frozen=True)
class Frame:
    content: bytes
    media_type: str
    simulated: bool = True


class Camera(Protocol):
    async def activate(self) -> None: ...
    async def capture(self) -> Frame: ...
    async def deactivate(self) -> None: ...


class VisionResult(BaseModel):
    # Saída observada do gateway de visão, sem copiar sua implementação/provedores.
    model_config = ConfigDict(extra="ignore")
    status: Literal["recognized", "rejected", "needs-secondary"]
    itemId: str | None
    candidateIds: list[str]
    confidence: float = Field(ge=0, le=1, allow_inf_nan=False)
    origin: str


@dataclass(frozen=True)
class Observation:
    result: VisionResult
    simulated: bool = True


class Vision(Protocol):
    async def classify(self, frame: Frame) -> Observation: ...


class CaptureService:
    def __init__(
        self,
        store: CycleStore,
        camera: Camera | None = None,
        vision: Vision | None = None,
        *,
        stabilization_seconds: float = 1.5,
    ):
        self.store = store
        self.camera = camera
        self.vision = vision
        self.stabilization_seconds = stabilization_seconds

    def _fail(self, event_id, expected, code):
        self.store.change(event_id, expected, "TECHNICAL_FAILURE", code=code)
        raise CycleError(code, 503)

    async def analyze(self, event_id: UUID) -> Observation:
        if self.store.get(event_id).state != "DOOR_CLOSED":
            raise CycleError("DOOR_CLOSED_CONFIRMATION_REQUIRED")
        if self.camera is None:
            self._fail(event_id, "DOOR_CLOSED", "CAMERA_NOT_INTEGRATED")
        if self.vision is None:
            self._fail(event_id, "DOOR_CLOSED", "VISION_NOT_INTEGRATED")
        self.store.change(event_id, "DOOR_CLOSED", "CAPTURING")
        try:
            # Estabilização só depois do estado fechado; não comprova fechamento.
            await asyncio.sleep(self.stabilization_seconds)
            frame = await self.camera.capture()
        except Exception:
            self._fail(event_id, "CAPTURING", "CAPTURE_FAILED")
        if not isinstance(frame, Frame) or not frame.content:
            self._fail(event_id, "CAPTURING", "CAPTURE_FAILED")
        if frame.simulated:
            self._fail(event_id, "CAPTURING", "SIMULATED_CAPTURE_BLOCKED")
        self.store.change(event_id, "CAPTURING", "CLASSIFYING")
        try:
            observation = await self.vision.classify(frame)
            if not isinstance(observation, Observation) or not isinstance(
                observation.result, VisionResult
            ):
                raise ValueError()
        except Exception:
            self._fail(event_id, "CLASSIFYING", "CLASSIFICATION_FAILED")
        if observation.simulated:
            self._fail(event_id, "CLASSIFYING", "SIMULATED_CLASSIFICATION_BLOCKED")
        if observation.result.status == "needs-secondary":
            self._fail(event_id, "CLASSIFYING", "CLASSIFICATION_INCONCLUSIVE")
        state = (
            "RETURN_REQUIRED" if observation.result.status == "rejected" else "REVIEW"
        )
        self.store.change(
            event_id,
            "CLASSIFYING",
            state,
            vision_result=observation.result.model_dump_json(),
        )
        # Frame só em memória; nunca imagem no SQLite. Retorno não registra evento.
        return observation
