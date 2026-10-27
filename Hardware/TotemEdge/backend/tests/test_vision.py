"""Somente imagens em memória e provedores controlados; nenhum serviço hospedado."""

import asyncio
import ast
from dataclasses import replace
from io import BytesIO
import json
from pathlib import Path
import threading
from unittest.mock import Mock

from fastapi.testclient import TestClient
import httpx2 as httpx
from PIL import Image
import pytest

from app.main import create_app
from app.services.capture import CaptureService, Frame
from app.services.vision import (
    GeminiProvider,
    InternalVision,
    MAX_IMAGE_BYTES,
    MAX_RESPONSE_BYTES,
    RekognitionProvider,
    VisionError,
    VisionSettings,
    validate_frame,
    validate_result,
)
from app.services.vision_policy import classify_labels
from app.storage import CycleStore
from test_capture import CameraFixture
from test_sessions import seed_persisted_state


@pytest.fixture
def frame():
    buffer = BytesIO()
    Image.new("RGB", (16, 16), "white").save(buffer, format="PNG")
    return Frame(buffer.getvalue(), "image/png")


def result(status="recognized", *, origin="AWS_REKOGNITION"):
    return dict(
        status=status,
        itemId="cable" if status == "recognized" else None,
        candidateIds=["cable"],
        confidence=0.93,
        origin=origin,
    )


class ControlledProvider:
    # Mesmo frame marcado real não converte double em evidência real.
    simulated = True

    def __init__(self, answer):
        self.answer = answer
        self.calls = []

    async def analyze(self, frame, candidates):
        self.calls.append((frame, candidates))
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer


def gemini_body(decision="cable", confidence=0.96):
    return {
        "candidates": [
            {
                "finishReason": "STOP",
                "content": {
                    "parts": [
                        {
                            "text": json.dumps(
                                {"decision": decision, "confidence": confidence}
                            )
                        }
                    ]
                },
            }
        ]
    }


@pytest.mark.anyio
@pytest.mark.parametrize("status", ["recognized", "rejected"])
async def test_confident_primary_never_calls_gemini(frame, status):
    primary = ControlledProvider(result(status))
    secondary = ControlledProvider(AssertionError("must not call"))
    observation = await InternalVision(primary, secondary).classify(frame)
    assert observation.result.status == status
    assert observation.simulated
    assert len(primary.calls) == 1 and secondary.calls == []


@pytest.mark.anyio
@pytest.mark.parametrize("status", ["recognized", "rejected", "needs-secondary"])
async def test_selective_fallback_and_provenance(frame, status):
    primary = ControlledProvider(result("needs-secondary"))
    secondary = ControlledProvider(result(status, origin="GEMINI_FALLBACK"))
    observation = await InternalVision(primary, secondary).classify(
        replace(frame, simulated=False)
    )
    assert observation.result.status == status
    assert observation.simulated is True
    assert len(primary.calls) == len(secondary.calls) == 1
    assert secondary.calls[0][1] == ["cable"]


@pytest.mark.anyio
async def test_unconfigured_secondary_keeps_inconclusive(frame):
    observation = await InternalVision(
        ControlledProvider(result("needs-secondary")), None
    ).classify(frame)
    assert observation.result.status == "needs-secondary"
    assert observation.result.itemId is None


@pytest.mark.anyio
@pytest.mark.parametrize(
    "error",
    [
        TimeoutError("private"),
        OSError("private"),
        RuntimeError("private"),
        VisionError("PRIMARY_UNAVAILABLE"),
    ],
)
async def test_primary_failure_never_becomes_rejection_or_fallback(frame, error):
    secondary = ControlledProvider(result(origin="GEMINI_FALLBACK"))
    with pytest.raises(VisionError) as raised:
        await InternalVision(ControlledProvider(error), secondary).classify(frame)
    assert "private" not in str(raised.value)
    assert secondary.calls == []


@pytest.mark.anyio
async def test_missing_primary_is_not_secondary_only_mode(frame):
    secondary = ControlledProvider(result(origin="GEMINI_FALLBACK"))
    with pytest.raises(VisionError, match="PRIMARY_UNAVAILABLE"):
        await InternalVision(None, secondary).classify(frame)
    assert secondary.calls == []


@pytest.mark.parametrize(
    "override",
    [
        {"content": b""},
        {"content": b"x" * (MAX_IMAGE_BYTES + 1)},
        {"content": "not bytes"},
        {"media_type": "image/gif"},
        {"media_type": "image/jpeg"},
        {"media_type": "image/png; charset=utf-8"},
        {"content": b"\x89PNG\r\n\x1a\ninvalid"},
        {"simulated": "false"},
    ],
)
def test_invalid_images(frame, override):
    with pytest.raises(VisionError):
        validate_frame(replace(frame, **override))


def test_valid_jpeg_and_truncation():
    buffer = BytesIO()
    Image.new("RGB", (8, 8)).save(buffer, format="JPEG")
    validate_frame(Frame(buffer.getvalue(), "image/jpeg"))
    with pytest.raises(VisionError, match="INVALID_IMAGE_CONTENT"):
        validate_frame(Frame(buffer.getvalue()[:-20], "image/jpeg"))


def test_image_pixel_budget_and_animation(frame, monkeypatch):
    monkeypatch.setattr("app.services.vision.MAX_IMAGE_PIXELS", 10)
    with pytest.raises(VisionError, match="INVALID_IMAGE_CONTENT"):
        validate_frame(frame)
    monkeypatch.setattr("app.services.vision.MAX_IMAGE_PIXELS", 16_000_000)
    buffer = BytesIO()
    Image.new("RGB", (8, 8), "red").save(
        buffer,
        format="PNG",
        save_all=True,
        append_images=[Image.new("RGB", (8, 8), "blue")],
    )
    with pytest.raises(VisionError, match="INVALID_IMAGE_CONTENT"):
        validate_frame(Frame(buffer.getvalue(), "image/png"))


@pytest.mark.anyio
async def test_validation_precedes_any_provider(frame):
    primary = ControlledProvider(result())
    with pytest.raises(VisionError):
        await InternalVision(primary, None).classify(replace(frame, content=b"bad"))
    assert primary.calls == []


@pytest.mark.parametrize(
    "patch",
    [
        {"status": "anything"},
        {"status": []},
        {"itemId": "BATTERY"},
        {"itemId": "unknown"},
        {"itemId": None},
        {"candidateIds": ["new-id"]},
        {"candidateIds": ["cable", "cable"]},
        {"candidateIds": "cable"},
        {"candidateIds": [{}]},
        {"candidateIds": []},
        {"confidence": True},
        {"confidence": "0.9"},
        {"confidence": float("nan")},
        {"confidence": float("inf")},
        {"confidence": -0.1},
        {"confidence": 1.1},
        {"origin": "MANUAL_REVIEW"},
        {"labels": "raw-provider-data"},
        {"status": "rejected"},
    ],
)
def test_malformed_observations_rejected(patch):
    with pytest.raises(VisionError):
        validate_result({**result(), **patch}, "AWS_REKOGNITION")


@pytest.mark.anyio
@pytest.mark.parametrize(
    "labels",
    [
        None,
        {},
        [None],
        [{"Name": "Cable"}],
        [{"Name": 12, "Confidence": 99}],
        [{"Name": "Cable", "Confidence": "99"}],
        [{"Name": "Cable", "Confidence": float("nan")}],
        [{"Name": "Cable", "Confidence": 101}],
        [{"Name": "Cable", "Confidence": 90}] * 21,
    ],
)
async def test_rekognition_malformed_payloads(frame, monkeypatch, labels):
    provider = RekognitionProvider(
        VisionSettings(aws_key="fixture", aws_secret="fixture")
    )
    monkeypatch.setattr(provider, "_detect", lambda _: {"Labels": labels})
    with pytest.raises(VisionError, match="INVALID_PRIMARY_RESPONSE"):
        await provider.analyze(frame, [])


@pytest.mark.anyio
async def test_empty_labels_are_inconclusive(frame, monkeypatch):
    provider = RekognitionProvider(
        VisionSettings(aws_key="fixture", aws_secret="fixture")
    )
    monkeypatch.setattr(provider, "_detect", lambda _: {"Labels": []})
    assert (await provider.analyze(frame, []))["status"] == "needs-secondary"


def test_aws_call_preserves_limits_and_explicit_credentials(frame, monkeypatch):
    client = Mock()
    client.__enter__ = Mock(return_value=client)
    client.__exit__ = Mock(return_value=False)
    factory = Mock(return_value=client)
    monkeypatch.setattr("app.services.vision.boto3.client", factory)
    provider = RekognitionProvider(
        VisionSettings(aws_key="fixture", aws_secret="secret")
    )
    provider._detect(frame.content)
    config = factory.call_args.kwargs["config"]
    assert config.connect_timeout == 3 and config.read_timeout == 5
    assert config.retries == {"total_max_attempts": 1}
    assert config.proxies == {} and config.max_pool_connections == 1
    assert factory.call_args.kwargs["aws_access_key_id"] == "fixture"
    client.detect_labels.assert_called_once_with(
        Image={"Bytes": frame.content}, MaxLabels=20, MinConfidence=55
    )


@pytest.mark.anyio
async def test_cancelled_sdk_call_keeps_single_flight_until_thread_finishes(
    frame, monkeypatch
):
    provider = RekognitionProvider(
        VisionSettings(aws_key="fixture", aws_secret="fixture")
    )
    started, release = threading.Event(), threading.Event()

    def detect(_):
        started.set()
        assert release.wait(3)
        return {"Labels": [{"Name": "Cable", "Confidence": 95}]}

    monkeypatch.setattr(provider, "_detect", detect)
    task = asyncio.create_task(provider.analyze(frame, []))
    try:
        assert await asyncio.to_thread(started.wait, 2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        with pytest.raises(VisionError, match="VISION_BUSY"):
            await provider.analyze(frame, [])
    finally:
        release.set()
        for _ in range(100):
            if not provider._busy:
                break
            await asyncio.sleep(0.01)
    assert provider._busy is False


@pytest.mark.anyio
@pytest.mark.parametrize(
    "decision,status",
    [
        ("battery", "recognized"),
        ("cable", "recognized"),
        ("phone", "recognized"),
        ("small", "recognized"),
        ("rejected", "rejected"),
        ("inconclusive", "needs-secondary"),
    ],
)
async def test_gemini_structured_request_and_decisions(frame, decision, status):
    calls = []

    def upstream(request):
        calls.append(request)
        assert request.headers["x-goog-api-key"] == "test-secret"
        assert "test-secret" not in str(request.url)
        body = json.loads(request.content)
        assert (
            body["contents"][0]["parts"][1]["inline_data"]["mime_type"] == "image/png"
        )
        assert body["generationConfig"]["thinkingConfig"] == {
            "thinkingLevel": "minimal"
        }
        assert (
            "inconclusive"
            in body["generationConfig"]["responseSchema"]["properties"]["decision"][
                "enum"
            ]
        )
        return httpx.Response(200, json=gemini_body(decision))

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        raw = await GeminiProvider(
            http, VisionSettings(gemini_key="test-secret")
        ).analyze(frame, ["cable"])
    parsed = validate_result(raw, "GEMINI_FALLBACK")
    assert parsed.status == status and len(calls) == 1


@pytest.mark.anyio
@pytest.mark.parametrize("failure", [429, 503, "timeout", "network"])
@pytest.mark.parametrize("recover", [True, False])
async def test_gemini_transient_retry_is_bounded(frame, monkeypatch, failure, recover):
    calls, delays = [], []

    async def pause(delay):
        delays.append(delay)

    monkeypatch.setattr("app.services.vision.asyncio.sleep", pause)

    def upstream(request):
        calls.append(request)
        if len(calls) > 1 and recover:
            return httpx.Response(200, json=gemini_body())
        if failure == "timeout":
            raise httpx.ReadTimeout("private", request=request)
        if failure == "network":
            raise httpx.ConnectError("private", request=request)
        return httpx.Response(failure, text="private")

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        provider = GeminiProvider(http, VisionSettings(gemini_key="fixture"))
        if recover:
            assert (await provider.analyze(frame, []))["status"] == "recognized"
        else:
            with pytest.raises(VisionError, match="SECONDARY_UNAVAILABLE"):
                await provider.analyze(frame, [])
    assert len(calls) == 2 and delays == [1]


@pytest.mark.anyio
@pytest.mark.parametrize("status", [400, 401, 403, 404, 500, 302])
async def test_gemini_no_retry_or_redirect_on_other_http_status(frame, status):
    requests = []

    def upstream(request):
        requests.append(request)
        return httpx.Response(
            status, headers={"Location": "https://elsewhere.invalid/"}
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        with pytest.raises(VisionError, match="SECONDARY_UNAVAILABLE"):
            await GeminiProvider(http, VisionSettings(gemini_key="fixture")).analyze(
                frame, []
            )
    assert len(requests) == 1


@pytest.mark.anyio
@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"candidates": []},
        {"candidates": [{"finishReason": "SAFETY"}]},
        gemini_body("invented"),
        gemini_body("cable", "0.99"),
        gemini_body("cable", True),
        gemini_body("cable", -1),
        gemini_body("cable", float("nan")),
        gemini_body("cable", 2),
    ],
)
async def test_gemini_malformed_response_never_becomes_decision(frame, payload):
    # json.dumps permite NaN para testar a rejeição estrita do parser de decisão.
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, content=json.dumps(payload).encode())
        )
    ) as http:
        with pytest.raises(VisionError, match="INVALID_SECONDARY_RESPONSE"):
            await GeminiProvider(http, VisionSettings(gemini_key="fixture")).analyze(
                frame, []
            )


@pytest.mark.anyio
@pytest.mark.parametrize(
    "content",
    [b"not json", b"x" * (MAX_RESPONSE_BYTES + 1)],
    ids=["invalid-json", "oversized"],
)
async def test_gemini_invalid_json_and_oversized_response(frame, content):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, content=content))
    ) as http:
        with pytest.raises(VisionError, match="INVALID_SECONDARY_RESPONSE"):
            await GeminiProvider(http, VisionSettings(gemini_key="fixture")).analyze(
                frame, []
            )


@pytest.mark.parametrize(
    "config",
    [
        {"gemini_retries": 2},
        {"gemini_retries": -1},
        {"gemini_timeout": 11},
        {"gemini_timeout": float("nan")},
        {"gemini_timeout": 0},
        {"model": "../escape?key=private"},
    ],
)
def test_settings_cannot_expand_retry_timeout_or_endpoint(config):
    with pytest.raises(VisionError, match="INVALID_VISION_CONFIG"):
        VisionSettings(**config)
    assert "secret" not in repr(
        VisionSettings(gemini_key="secret", aws_secret="secret")
    )


@pytest.mark.anyio
async def test_capture_blocks_controlled_provider_and_does_not_persist_photo(
    frame, tmp_path, caplog
):
    store = CycleStore(tmp_path / "vision.sqlite3")
    event_id, _ = seed_persisted_state(store, "DOOR_CLOSED")
    service = InternalVision(ControlledProvider(result()), None)
    try:
        from app.cycles import CycleError

        with pytest.raises(CycleError) as raised:
            await CaptureService(
                store,
                CameraFixture(replace(frame, simulated=False)),
                service,
                stabilization_seconds=0,
            ).analyze(event_id)
        assert raised.value.code == "SIMULATED_CLASSIFICATION_BLOCKED"
        assert store.get(event_id).state == "TECHNICAL_FAILURE"
        assert store.get(event_id).receipt is None
        with store.transaction() as conn:
            row = conn.execute(
                "SELECT event_id, physical_confirmed, vision_result FROM cycles"
            ).fetchone()
            assert row[0] == str(event_id) and row[1] == 0 and row[2] is None
            assert frame.content not in conn.serialize()
        assert "PNG" not in caplog.text
    finally:
        store.close()


def test_lifespan_composes_service_but_keeps_routes_capture_and_readiness_blocked(
    configured_environment, healthy_body
):
    paths = []

    def upstream(request):
        paths.append(request.url.path)
        return httpx.Response(200, json=healthy_body)

    with TestClient(
        create_app(transport=httpx.MockTransport(upstream)), base_url="http://127.0.0.1"
    ) as client:
        assert isinstance(client.app.state.vision, InternalVision)
        assert client.app.state.capture.vision is None
        assert client.app.state.capture.camera is None
        assert paths == []  # startup não descobre credenciais nem consulta IA.
        body = client.get("/local/status").json()
        assert body["status"] == "OFFLINE" and body["can_start_deposit"] is False
        schema = client.get("/openapi.json").json()["paths"]
        assert not any("vision" in path or "capture" in path for path in schema)
        assert all(path.endswith("health-v1") for path in paths)


def test_policy_is_reused_without_importing_ui_at_runtime():
    source = (
        Path(__file__).resolve().parents[4]
        / "Software/apps/totem_ui/edge_vision_service.py"
    )
    original = next(
        node
        for node in ast.parse(source.read_text(encoding="utf-8")).body
        if isinstance(node, ast.FunctionDef) and node.name == "classify_labels"
    )
    import inspect

    current = ast.parse(inspect.getsource(classify_labels)).body[0]
    assert ast.dump(original) == ast.dump(current)


@pytest.mark.parametrize(
    "labels,status,item,candidates",
    [
        (
            [("Electronics", 100), ("Printed Circuit Board", 92)],
            "recognized",
            "small",
            ["small"],
        ),
        ([("Dog", 99)], "rejected", None, []),
        ([("Cable", 62)], "needs-secondary", None, ["cable"]),
        ([("Electronics", 99), ("Adapter", 96)], "needs-secondary", None, ["cable"]),
        (
            [("Electronics", 99), ("Mobile Phone", 98), ("Remote Control", 95)],
            "needs-secondary",
            None,
            ["small", "phone"],
        ),
        ([("Can", 90), ("Cylinder", 72)], "needs-secondary", None, ["battery"]),
        (
            [("Plastic", 99), ("Beverage", 91), ("Bottle", 88), ("Lightbulb", 56)],
            "rejected",
            None,
            [],
        ),
        (
            [("Hand", 94), ("Finger", 91), ("Object", 58)],
            "needs-secondary",
            None,
            ["unknown"],
        ),
        (
            [("Hand", 94), ("Marker", 58), ("Crayon", 56)],
            "needs-secondary",
            None,
            ["battery"],
        ),
    ],
)
def test_original_classification_cases(labels, status, item, candidates):
    raw = classify_labels(
        [{"Name": name, "Confidence": score} for name, score in labels]
    )
    assert (raw["status"], raw["itemId"], raw["candidateIds"]) == (
        status,
        item,
        candidates,
    )


@pytest.mark.anyio
async def test_low_confidence_primary_uses_existing_js_threshold(frame):
    primary = ControlledProvider({**result(), "confidence": 0.5})
    secondary = ControlledProvider(result(origin="GEMINI_FALLBACK"))
    observation = await InternalVision(primary, secondary).classify(frame)
    assert observation.result.origin == "GEMINI_FALLBACK"
    assert len(secondary.calls) == 1


@pytest.mark.anyio
@pytest.mark.parametrize("stage", ["primary", "secondary"])
async def test_total_deadline_cancels_provider_and_releases_service(
    frame, monkeypatch, stage
):
    timeout = asyncio.timeout
    monkeypatch.setattr("app.services.vision.asyncio.timeout", lambda _: timeout(0.01))
    cancelled = []

    class HangingProvider:
        simulated = True

        async def analyze(self, frame, candidates):
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.append(True)

    service = InternalVision(
        HangingProvider()
        if stage == "primary"
        else ControlledProvider(result("needs-secondary")),
        HangingProvider(),
    )
    with pytest.raises(VisionError, match="VISION_TIMEOUT"):
        await service.classify(frame)
    assert cancelled == [True] and service._busy is False


@pytest.mark.anyio
async def test_concurrent_classification_does_not_queue_frames(frame):
    started, release = asyncio.Event(), asyncio.Event()

    class WaitingProvider(ControlledProvider):
        async def analyze(self, frame, candidates):
            started.set()
            await release.wait()
            return result()

    service = InternalVision(WaitingProvider(result()), None)
    task = asyncio.create_task(service.classify(frame))
    await started.wait()
    try:
        with pytest.raises(VisionError, match="VISION_BUSY"):
            await service.classify(frame)
    finally:
        release.set()
        await task


@pytest.mark.anyio
@pytest.mark.parametrize(
    "decision,status",
    [
        ("battery", "recognized"),
        ("rejected", "rejected"),
        ("inconclusive", "needs-secondary"),
    ],
)
async def test_complete_adapter_cascade_with_image_and_controlled_responses(
    frame, monkeypatch, decision, status
):
    settings = VisionSettings(
        aws_key="fixture", aws_secret="fixture", gemini_key="fixture"
    )
    primary = RekognitionProvider(settings)
    monkeypatch.setattr(
        primary, "_detect", lambda _: {"Labels": [{"Name": "Cable", "Confidence": 62}]}
    )
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json=gemini_body(decision))
        )
    ) as http:
        observation = await InternalVision(
            primary, GeminiProvider(http, settings)
        ).classify(frame)
    assert observation.result.origin == "GEMINI_FALLBACK"
    assert observation.result.status == status and observation.simulated is True


@pytest.mark.anyio
async def test_credentials_missing_do_not_make_network_requests(frame, monkeypatch):
    factory = Mock(side_effect=AssertionError("must not create SDK"))
    monkeypatch.setattr("app.services.vision.boto3.client", factory)
    with pytest.raises(VisionError, match="PRIMARY_UNAVAILABLE"):
        await RekognitionProvider(VisionSettings()).analyze(frame, [])
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: pytest.fail("network"))
    ) as http:
        with pytest.raises(VisionError, match="SECONDARY_UNAVAILABLE"):
            await GeminiProvider(http, VisionSettings()).analyze(frame, [])
    factory.assert_not_called()


def test_invalid_environment_disables_internal_service_without_affecting_liveness(
    monkeypatch,
):
    monkeypatch.setenv("BINGO_GEMINI_TRANSIENT_RETRIES", "99")
    with TestClient(create_app(), base_url="http://127.0.0.1") as client:
        assert client.app.state.vision.primary is None
        assert client.get("/health").json() == {"status": "ok"}
        assert client.get("/local/status").json()["can_start_deposit"] is False
