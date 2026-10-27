"""Análise interna em memória. Não conhece sessões, SQLite, economia ou hardware."""

import asyncio
import base64
from dataclasses import dataclass, field
from io import BytesIO
import json
import math
import os
import re
from typing import Protocol
import warnings

import boto3
from botocore.config import Config
import httpx2 as httpx
from PIL import Image

from app.services.capture import Frame, Observation, VisionResult
from app.services.vision_policy import classify_labels

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 16_000_000
MAX_RESPONSE_BYTES = 64 * 1024
ITEM_IDS = {"battery", "cable", "phone", "small", "unknown"}
DECISIONS = ["battery", "cable", "phone", "small", "rejected", "inconclusive"]


class VisionError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def number(value, lower, upper):
    return (
        type(value) in (int, float) and lower <= value <= upper and math.isfinite(value)
    )


def validate_frame(frame: Frame) -> None:
    if (
        not isinstance(frame, Frame)
        or type(frame.content) is not bytes
        or type(frame.simulated) is not bool
        or not 0 < len(frame.content) <= MAX_IMAGE_BYTES
    ):
        raise VisionError("INVALID_IMAGE_SIZE_OR_FRAME")
    formats = {"image/png": "PNG", "image/jpeg": "JPEG"}
    if type(frame.media_type) is not str or frame.media_type not in formats:
        raise VisionError("UNSUPPORTED_IMAGE_TYPE")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(frame.content)) as image:
                if (
                    image.format != formats[frame.media_type]
                    or image.width * image.height > MAX_IMAGE_PIXELS
                    or getattr(image, "n_frames", 1) != 1
                ):
                    raise ValueError()
                image.verify()
            # verify() sozinho não detecta todos os JPEGs truncados.
            with Image.open(BytesIO(frame.content)) as image:
                image.load()
    except Exception:
        raise VisionError("INVALID_IMAGE_CONTENT") from None


def validate_result(raw, origin: str) -> VisionResult:
    if (
        type(raw) is not dict
        or set(raw) != {"status", "itemId", "candidateIds", "confidence", "origin"}
        or raw["origin"] != origin
        or not number(raw["confidence"], 0, 1)
        or type(raw["candidateIds"]) is not list
        or len(raw["candidateIds"]) > len(ITEM_IDS)
        or any(
            type(item) is not str or item not in ITEM_IDS
            for item in raw["candidateIds"]
        )
        or len(set(raw["candidateIds"])) != len(raw["candidateIds"])
        or type(raw["status"]) is not str
        or raw["status"] not in {"recognized", "rejected", "needs-secondary"}
    ):
        raise VisionError("INVALID_PROVIDER_RESPONSE")
    if raw["status"] == "recognized":
        if (
            type(raw["itemId"]) is not str
            or raw["itemId"] not in ITEM_IDS - {"unknown"}
            or raw["itemId"] not in raw["candidateIds"]
        ):
            raise VisionError("INVALID_PROVIDER_RESPONSE")
    elif raw["itemId"] is not None:
        raise VisionError("INVALID_PROVIDER_RESPONSE")
    return VisionResult.model_validate(raw)


@dataclass(frozen=True)
class VisionSettings:
    aws_key: str = field(default="", repr=False)
    aws_secret: str = field(default="", repr=False)
    aws_token: str = field(default="", repr=False)
    region: str = "sa-east-1"
    gemini_key: str = field(default="", repr=False)
    model: str = "gemini-flash-lite-latest"
    gemini_timeout: float = 10
    gemini_retries: int = 1

    def __post_init__(self):
        if (
            not re.fullmatch(r"[a-z]{2}(?:-[a-z]+)+-\d", self.region)
            or not re.fullmatch(r"[A-Za-z0-9._-]{1,100}", self.model)
            or not number(self.gemini_timeout, 0.1, 10)
            or type(self.gemini_retries) is not int
            or self.gemini_retries not in (0, 1)
        ):
            raise VisionError("INVALID_VISION_CONFIG")

    @classmethod
    def from_environment(cls):
        try:
            return cls(
                aws_key=os.getenv("AWS_ACCESS_KEY_ID", ""),
                aws_secret=os.getenv("AWS_SECRET_ACCESS_KEY", ""),
                aws_token=os.getenv("AWS_SESSION_TOKEN", ""),
                region=os.getenv("AWS_REGION", "sa-east-1"),
                gemini_key=os.getenv("GEMINI_API_KEY", ""),
                model=os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest"),
                gemini_timeout=float(os.getenv("BINGO_GEMINI_TIMEOUT_SECONDS", "10")),
                gemini_retries=int(os.getenv("BINGO_GEMINI_TRANSIENT_RETRIES", "1")),
            )
        except (TypeError, ValueError):
            raise VisionError("INVALID_VISION_CONFIG") from None


class Provider(Protocol):
    # Doubles/transportes controlados permanecem simulados por padrão.
    simulated: bool

    async def analyze(self, frame: Frame, candidates: list[str]) -> dict: ...


class RekognitionProvider:
    simulated = False

    def __init__(self, settings: VisionSettings):
        self.settings = settings
        self._busy = False

    def _detect(self, content):
        # Credenciais explícitas: sem descoberta IMDS/perfil/rede no startup.
        with boto3.client(
            "rekognition",
            region_name=self.settings.region,
            aws_access_key_id=self.settings.aws_key,
            aws_secret_access_key=self.settings.aws_secret,
            aws_session_token=self.settings.aws_token or None,
            config=Config(
                connect_timeout=3,
                read_timeout=5,
                retries={"total_max_attempts": 1},
                proxies={},
                ignore_configured_endpoint_urls=True,
                max_pool_connections=1,
            ),
        ) as client:
            return client.detect_labels(
                Image={"Bytes": content}, MaxLabels=20, MinConfidence=55
            )

    async def analyze(self, frame, candidates):
        if not self.settings.aws_key or not self.settings.aws_secret:
            raise VisionError("PRIMARY_UNAVAILABLE")
        if self._busy:
            raise VisionError("VISION_BUSY")
        self._busy = True
        task = asyncio.create_task(asyncio.to_thread(self._detect, frame.content))

        def finished(done):
            self._busy = False
            if not done.cancelled():
                done.exception()  # Consumir falha tardia sem logar bytes/secrets.

        task.add_done_callback(finished)
        try:
            # Timeout/cancelamento não libera outro trabalho enquanto a thread vive.
            async with asyncio.timeout(10):
                response = await asyncio.shield(task)
        except TimeoutError:
            raise VisionError("PRIMARY_TIMEOUT") from None
        except Exception:
            raise VisionError("PRIMARY_UNAVAILABLE") from None
        if type(response) is not dict or type(response.get("Labels")) is not list:
            raise VisionError("INVALID_PRIMARY_RESPONSE")
        labels = response["Labels"]
        if len(labels) > 20 or any(
            type(label) is not dict
            or type(label.get("Name")) is not str
            or not 0 < len(label["Name"]) <= 256
            or not number(label.get("Confidence"), 0, 100)
            for label in labels
        ):
            raise VisionError("INVALID_PRIMARY_RESPONSE")
        if not labels:
            return dict(
                status="needs-secondary",
                itemId=None,
                candidateIds=[],
                confidence=0.0,
                origin="AWS_REKOGNITION",
            )
        return classify_labels(labels)


class GeminiProvider:
    simulated = False

    def __init__(self, client: httpx.AsyncClient, settings: VisionSettings):
        self.client = client
        self.settings = settings

    async def _request(self, body):
        endpoint = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{self.settings.model}:generateContent"
        )
        async with asyncio.timeout(self.settings.gemini_timeout):
            async with self.client.stream(
                "POST",
                endpoint,
                json=body,
                headers={"x-goog-api-key": self.settings.gemini_key},
                timeout=self.settings.gemini_timeout,
                follow_redirects=False,
            ) as response:
                if response.status_code != 200:
                    return response.status_code, None
                data = bytearray()
                async for chunk in response.aiter_bytes():
                    data.extend(chunk)
                    if len(data) > MAX_RESPONSE_BYTES:
                        raise VisionError("INVALID_SECONDARY_RESPONSE")
                return 200, json.loads(data)

    async def analyze(self, frame, candidates):
        if not self.settings.gemini_key:
            raise VisionError("SECONDARY_UNAVAILABLE")
        # Prompt/schema herdados; inconclusão explícita corrige ambiguidade do legado.
        prompt = (
            "Classifique o unico objeto apresentado ao Totem BinGo. "
            "Nao trate mao, pessoa ou ambiente como objeto principal. "
            "Use battery para pilha/bateria; cable para cabo, fio, carregador ou "
            "adaptador; phone para celular; small para outro eletronico pequeno "
            "como mouse, fone, teclado, controle, calculadora, placa ou lampada. "
            "Use rejected somente para objeto claramente nao eletronico. "
            "Use inconclusive para duvida, imagem vazia, risco, item grande ou "
            "quando nao for possivel confirmar. Nao presuma seguranca fisica. "
            "Para pilhas observe formato, conectores e inscricoes AA/AAA/volts. "
            f"Candidatos do Rekognition (apenas pistas): {', '.join(candidates)}."
        )
        body = {
            "contents": [
                {
                    "parts": [
                        {"text": prompt},
                        {
                            "inline_data": {
                                "mime_type": frame.media_type,
                                "data": base64.b64encode(frame.content).decode("ascii"),
                            }
                        },
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0,
                "thinkingConfig": {"thinkingLevel": "minimal"},
                "responseMimeType": "application/json",
                "responseSchema": {
                    "type": "object",
                    "properties": {
                        "decision": {"type": "string", "enum": DECISIONS},
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                    "required": ["decision", "confidence"],
                },
            },
        }
        for attempt in range(self.settings.gemini_retries + 1):
            try:
                status, payload = await self._request(body)
            except (TimeoutError, httpx.TimeoutException, httpx.NetworkError):
                status, payload = 503, None
            except VisionError:
                raise
            except Exception:
                raise VisionError("INVALID_SECONDARY_RESPONSE") from None
            if status == 200:
                break
            if status not in (429, 503) or attempt == self.settings.gemini_retries:
                raise VisionError("SECONDARY_UNAVAILABLE")
            await asyncio.sleep(1)
        try:
            (candidate,) = payload["candidates"]
            (part,) = candidate["content"]["parts"]
            if candidate.get("finishReason") != "STOP":
                raise ValueError()
            decision = json.loads(part["text"])
            if (
                type(decision) is not dict
                or set(decision) != {"decision", "confidence"}
                or decision["decision"] not in DECISIONS
                or not number(decision["confidence"], 0, 1)
            ):
                raise ValueError()
        except Exception:
            raise VisionError("INVALID_SECONDARY_RESPONSE") from None
        item = decision["decision"]
        status = (
            "needs-secondary"
            if item == "inconclusive"
            else "rejected"
            if item == "rejected"
            else "recognized"
        )
        return dict(
            status=status,
            itemId=item if status == "recognized" else None,
            candidateIds=list(dict.fromkeys([item, *candidates]))
            if status == "recognized"
            else candidates,
            confidence=decision["confidence"],
            origin="GEMINI_FALLBACK",
        )


class InternalVision:
    """Implementa Vision.classify sem acesso a estado/registro ou revisão humana."""

    def __init__(self, primary: Provider | None, secondary: Provider | None):
        self.primary = primary
        self.secondary = secondary
        self._busy = False

    async def classify(self, frame: Frame) -> Observation:
        if self._busy:
            raise VisionError("VISION_BUSY")
        self._busy = True
        try:
            validate_frame(frame)
            if self.primary is None:
                raise VisionError("PRIMARY_UNAVAILABLE")
            async with asyncio.timeout(10):
                raw = await self.primary.analyze(frame, [])
            result = validate_result(raw, "AWS_REKOGNITION")
            # Mesmo limiar 0,75 do provider JS; não acrescenta critério secundário.
            if result.status == "recognized" and result.confidence < 0.75:
                result = result.model_copy(
                    update={"status": "needs-secondary", "itemId": None}
                )
            simulated = frame.simulated or getattr(self.primary, "simulated", True)
            if result.status == "needs-secondary" and self.secondary is not None:
                async with asyncio.timeout(21):
                    raw = await self.secondary.analyze(frame, list(result.candidateIds))
                result = validate_result(raw, "GEMINI_FALLBACK")
                simulated = simulated or getattr(self.secondary, "simulated", True)
            return Observation(result, simulated=simulated)
        except VisionError:
            raise
        except TimeoutError:
            raise VisionError("VISION_TIMEOUT") from None
        except Exception:
            raise VisionError("VISION_PROVIDER_FAILED") from None
        finally:
            self._busy = False


def build_internal_vision(client: httpx.AsyncClient) -> InternalVision:
    try:
        settings = VisionSettings.from_environment()
    except VisionError:
        return InternalVision(None, None)
    return InternalVision(
        RekognitionProvider(settings),
        GeminiProvider(client, settings) if settings.gemini_key else None,
    )
