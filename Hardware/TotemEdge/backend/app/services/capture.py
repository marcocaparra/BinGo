"""Orquestra captura; acesso ao dispositivo e análise permanecem separados."""

import asyncio
from dataclasses import dataclass, replace
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
    async def capture(self, capture_id: UUID | None = None) -> Frame: ...
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
    observations: tuple[VisionResult, ...] = ()


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

    async def acquire(self, capture_id: UUID) -> Frame:
        """Acquire bytes once; the caller must reserve a durable session intent."""
        if self.camera is None:
            raise CycleError("CAMERA_NOT_INTEGRATED", 503)
        try:
            await self.camera.activate()
            return await self.camera.capture(capture_id)
        finally:
            await self.camera.deactivate()

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

    async def capture_only(self, event_id: UUID, capture_id: UUID) -> Frame:
        """3C.3.0: reserve once after durable closure; never classify or move."""
        if self.camera is None:
            raise CycleError("CAMERA_NOT_INTEGRATED", 503)
        with self.store.transaction() as conn:
            row = self.store._row(conn, event_id)
            source = "SIMULATED" if row["simulated"] else "PHYSICAL"
            closed = conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE event_id=? AND operation='CLOSE_INSERTION_DOOR' AND source=? AND phase='COMPLETED' AND result='SUCCEEDED'",
                (str(event_id), source),
            ).fetchone()
            if row["state"] != "DOOR_CLOSED" or not closed:
                raise CycleError("DOOR_CLOSED_CONFIRMATION_REQUIRED")
            if self.store.mechanical.has_risk(conn, event_id):
                raise CycleError("MECHANICAL_RESULT_UNKNOWN", 503)
            self.store._record(conn, row, "CAPTURING", code="CAMERA_CAPTURE_REQUESTED")
            simulated = bool(row["simulated"])
        try:
            # Managed cameras require a durable intent identifier; legacy analyze
            # retains its existing contract and remains unconnected to providers.
            frame = await self.acquire(capture_id)
            return replace(frame, simulated=frame.simulated or simulated)
        except asyncio.CancelledError:
            self.store.change(
                event_id,
                "CAPTURING",
                "TECHNICAL_FAILURE",
                code="CAMERA_CAPTURE_INTERRUPTED",
            )
            raise
        except Exception:
            self.store.change(
                event_id, "CAPTURING", "TECHNICAL_FAILURE", code="CAMERA_CAPTURE_FAILED"
            )
            raise
