import asyncio

import httpx2 as httpx
import pytest

from app.clients.supabase import SupabaseEdgeClient
from app.config import SupabaseSettings
from app.services.status import LocalStatusService


@pytest.mark.anyio
async def test_authenticated_health_uses_only_official_machine_headers(
    configured_environment, healthy_body
):
    requests = []

    def upstream(request):
        requests.append(request)
        assert request.method == "GET"
        assert str(request.url) == (
            "https://backend.example.invalid/functions/v1/health-v1"
        )
        assert (
            request.headers["X-Machine-Id"]
            == configured_environment["BINGO_MACHINE_ID"]
        )
        assert (
            request.headers["X-Api-Key"]
            == configured_environment["BINGO_MACHINE_API_KEY"]
        )
        assert "Authorization" not in request.headers
        assert "apikey" not in request.headers
        assert request.content == b""
        assert set(request.extensions["timeout"].values()) == {2.5}
        return httpx.Response(200, json=healthy_body)

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        result = await SupabaseEdgeClient(http).check_health()

    assert result.available is True
    assert result.outcome == "AVAILABLE"
    assert result.http_status == 200
    assert len(requests) == 1
    assert "private-test-fixture" not in repr(result)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "field", ["status", "can_start_deposit", "scope", "checked_at"]
)
async def test_missing_health_fields_fail_closed(
    configured_environment, healthy_body, field
):
    healthy_body.pop(field)
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=healthy_body))
    ) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "UNEXPECTED_RESPONSE"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "update",
    [
        {"status": "UNAVAILABLE"},
        {"can_start_deposit": False},
        {"can_start_deposit": "true"},
        {"can_start_deposit": 1},
        {"scope": "LOCAL"},
        {"checked_at": None},
        {"checked_at": "invalid"},
        {"checked_at": "2026-10-07T12:00:00"},
    ],
)
async def test_inconsistent_health_fields_fail_closed(
    configured_environment, healthy_body, update
):
    healthy_body.update(update)
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=healthy_body))
    ) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "UNEXPECTED_RESPONSE"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "code,body,outcome",
    [
        (503, {"status": "UNAVAILABLE", "can_start_deposit": False}, "UNAVAILABLE"),
        (
            503,
            {"status": "AVAILABLE", "can_start_deposit": True},
            "UNEXPECTED_RESPONSE",
        ),
        (
            401,
            {"status": "AVAILABLE", "can_start_deposit": True},
            "AUTHENTICATION_FAILED",
        ),
        (404, {}, "HTTP_ERROR"),
        (429, {}, "HTTP_ERROR"),
        (500, {}, "HTTP_ERROR"),
        (502, {}, "HTTP_ERROR"),
        (204, {}, "HTTP_ERROR"),
    ],
)
async def test_negative_readiness_and_http_failures_are_distinct(
    configured_environment, healthy_body, code, body, outcome
):
    healthy_body.update(body)
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(code, json=healthy_body))
    ) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == outcome
    assert result.http_status == code


@pytest.mark.anyio
@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, json=[]),
        httpx.Response(200, json=None),
        httpx.Response(
            200, content=b"not-json", headers={"Content-Type": "application/json"}
        ),
        httpx.Response(
            200, content=b"\xff", headers={"Content-Type": "application/json"}
        ),
        httpx.Response(200, text="{}"),
        httpx.Response(
            200,
            content=b"[" * 2000 + b"0" + b"]" * 2000,
            headers={"Content-Type": "application/json"},
        ),
        httpx.Response(503, json={"error": {"message": "private-test-fixture"}}),
    ],
)
async def test_malformed_responses_are_sanitized(configured_environment, response):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: response)
    ) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "UNEXPECTED_RESPONSE"
    assert "private-test-fixture" not in repr(result)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "error_type,outcome",
    [
        (httpx.ConnectTimeout, "TIMEOUT"),
        (httpx.ReadTimeout, "TIMEOUT"),
        (httpx.PoolTimeout, "TIMEOUT"),
        (httpx.ConnectError, "CONNECTION_ERROR"),
        (httpx.ReadError, "CONNECTION_ERROR"),
        (httpx.RemoteProtocolError, "UNEXPECTED_RESPONSE"),
        (httpx.DecodingError, "UNEXPECTED_RESPONSE"),
        (httpx.ProxyError, "HTTP_ERROR"),
    ],
)
async def test_transport_failures_do_not_escape_or_retry(
    configured_environment, error_type, outcome
):
    requests = []

    def upstream(request):
        requests.append(request)
        raise error_type("private-test-fixture", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == outcome
    assert result.http_status is None
    assert len(requests) == 1
    assert "private-test-fixture" not in repr(result)


@pytest.mark.anyio
async def test_redirect_is_not_followed_even_if_http_client_enables_it(
    configured_environment,
):
    requests = []

    def upstream(request):
        requests.append(request)
        return httpx.Response(
            302, headers={"Location": "https://other.example.invalid"}
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(upstream), follow_redirects=True
    ) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "HTTP_ERROR"
    assert len(requests) == 1


@pytest.mark.anyio
async def test_url_rejected_by_http_transport_is_sanitized(configured_environment):
    def upstream(_):
        raise httpx.InvalidURL("private-test-fixture")

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "INVALID_CONFIGURATION"
    assert "private-test-fixture" not in repr(result)


@pytest.mark.anyio
async def test_total_timeout_interrupts_a_stalled_request(
    configured_environment, monkeypatch
):
    monkeypatch.setenv("BINGO_BACKEND_TIMEOUT_SECONDS", "0.01")

    async def upstream(_):
        await asyncio.Event().wait()
        pytest.fail("A consulta deveria ter sido cancelada pelo timeout total.")

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == "TIMEOUT"


@pytest.mark.anyio
async def test_api_key_is_not_trimmed_or_normalized(
    configured_environment, monkeypatch, healthy_body
):
    key = "  Private-Test-Fixture  "
    monkeypatch.setenv("BINGO_MACHINE_API_KEY", key)

    def upstream(request):
        assert request.headers["X-Api-Key"] == key
        return httpx.Response(200, json=healthy_body)

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        assert (await SupabaseEdgeClient(http).check_health()).available is True
    assert key not in repr(SupabaseSettings.from_environment())


@pytest.mark.anyio
@pytest.mark.parametrize(
    "url",
    ["http://127.0.0.1:54321/", "http://localhost:54321", "http://[::1]:54321"],
)
async def test_local_supabase_urls_are_supported(
    configured_environment, monkeypatch, healthy_body, url
):
    monkeypatch.setenv("BINGO_SUPABASE_URL", url)

    def upstream(request):
        assert str(request.url) == f"{url.rstrip('/')}/functions/v1/health-v1"
        return httpx.Response(200, json=healthy_body)

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        assert (await SupabaseEdgeClient(http).check_health()).available is True


@pytest.mark.anyio
@pytest.mark.parametrize(
    "name,value,outcome",
    [
        ("BINGO_SUPABASE_URL", "", "NOT_CONFIGURED"),
        ("BINGO_MACHINE_ID", "", "NOT_CONFIGURED"),
        ("BINGO_MACHINE_API_KEY", "", "NOT_CONFIGURED"),
        (
            "BINGO_SUPABASE_URL",
            "http://remote.example.invalid",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_SUPABASE_URL",
            "https://private-test-fixture@backend.example.invalid",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_SUPABASE_URL",
            "https://backend.example.invalid/functions/v1",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_SUPABASE_URL",
            "https://backend.example.invalid?key=private-test-fixture",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_SUPABASE_URL",
            "https://backend.example.invalid#fragment",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_SUPABASE_URL",
            "https://backend.example.invalid:wrong",
            "INVALID_CONFIGURATION",
        ),
        ("BINGO_SUPABASE_URL", "https://[broken", "INVALID_CONFIGURATION"),
        (
            "BINGO_SUPABASE_URL",
            "https://backend.example.invalid\n",
            "INVALID_CONFIGURATION",
        ),
        ("BINGO_MACHINE_ID", "not-a-uuid", "INVALID_CONFIGURATION"),
        (
            "BINGO_MACHINE_ID",
            "00000000000040008000000000000001",
            "INVALID_CONFIGURATION",
        ),
        (
            "BINGO_MACHINE_API_KEY",
            "private-test-fixture\r\nInjected: yes",
            "INVALID_CONFIGURATION",
        ),
        ("BINGO_MACHINE_API_KEY", "chave-não-ascii", "INVALID_CONFIGURATION"),
        ("BINGO_BACKEND_TIMEOUT_SECONDS", "invalid", "INVALID_CONFIGURATION"),
        ("BINGO_BACKEND_TIMEOUT_SECONDS", "0", "INVALID_CONFIGURATION"),
        ("BINGO_BACKEND_TIMEOUT_SECONDS", "-1", "INVALID_CONFIGURATION"),
        ("BINGO_BACKEND_TIMEOUT_SECONDS", "nan", "INVALID_CONFIGURATION"),
        ("BINGO_BACKEND_TIMEOUT_SECONDS", "inf", "INVALID_CONFIGURATION"),
    ],
)
async def test_invalid_configuration_skips_network(
    configured_environment, monkeypatch, name, value, outcome
):
    monkeypatch.setenv(name, value)

    def upstream(_):
        pytest.fail("Configuração ausente/inválida não deve gerar tráfego.")

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        result = await SupabaseEdgeClient(http).check_health()
    assert result.available is False
    assert result.outcome == outcome
    assert "private-test-fixture" not in repr(result)


@pytest.mark.anyio
async def test_central_readiness_changes_never_enable_local_operation(
    configured_environment, healthy_body
):
    calls = []

    def upstream(request):
        calls.append(request)
        if len(calls) == 2:
            raise httpx.ReadTimeout("private-test-fixture", request=request)
        return httpx.Response(200, json=healthy_body)

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
        service = LocalStatusService(SupabaseEdgeClient(http))
        snapshots = [await service.check_status() for _ in range(3)]

    assert [snapshot.central_backend.available for snapshot in snapshots] == [
        True,
        False,
        True,
    ]
    assert [snapshot.central_backend.outcome for snapshot in snapshots] == [
        "AVAILABLE",
        "TIMEOUT",
        "AVAILABLE",
    ]
    assert all(snapshot.local.status == "OFFLINE" for snapshot in snapshots)
    assert all(snapshot.local.can_start_deposit is False for snapshot in snapshots)
    assert len(calls) == 3
