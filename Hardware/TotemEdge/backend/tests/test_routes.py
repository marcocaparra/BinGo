import socket

import httpx2 as httpx
import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client():
    with TestClient(create_app()) as test_client:
        yield test_client


def assert_safe_status(response):
    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "no-store"
    assert response.json() == {
        "status": "OFFLINE",
        "can_start_deposit": False,
        "message": (
            "Totem temporariamente indisponível. Estamos sem conexão no momento."
        ),
    }


def test_process_health_preserves_existing_contract(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_local_status_is_safe_even_when_process_is_healthy(client):
    assert client.get("/health").status_code == 200
    assert_safe_status(client.get("/local/status"))


@pytest.mark.parametrize("configured", [False, True])
def test_configuration_does_not_enable_deposits_or_expose_secrets(
    monkeypatch, configured, healthy_body
):
    config = {
        "BINGO_SUPABASE_URL": "https://backend.example.invalid",
        "BINGO_MACHINE_ID": "00000000-0000-4000-8000-000000000001",
        "BINGO_MACHINE_API_KEY": "private-test-fixture",
        "AWS_ACCESS_KEY_ID": "private-aws-fixture",
        "GEMINI_API_KEY": "private-gemini-fixture",
    }
    for name, value in config.items():
        if configured:
            monkeypatch.setenv(name, value)
        else:
            monkeypatch.delenv(name, raising=False)

    def reject_network(*args, **kwargs):
        pytest.fail("Rotas iniciais não devem consultar serviços externos.")

    calls = []

    def upstream(request):
        calls.append(request)
        return httpx.Response(200, json=healthy_body)

    with TestClient(create_app(transport=httpx.MockTransport(upstream))) as client:
        # Windows usa um socketpair loopback para iniciar o event loop do teste.
        # As chamadas centrais usam somente o transporte simulado.
        monkeypatch.setattr(socket.socket, "connect", reject_network)
        assert client.get("/health").json() == {"status": "ok"}
        response = client.get("/local/status")
        assert_safe_status(response)
        for value in config.values():
            assert value not in response.text
    assert len(calls) == int(configured)


@pytest.mark.parametrize("code", [200, 401, 503, 500])
def test_local_route_stays_safe_for_central_responses(
    configured_environment, healthy_body, code
):
    if code == 503:
        healthy_body.update(status="UNAVAILABLE", can_start_deposit=False)
    calls = []

    def upstream(request):
        calls.append(request)
        return httpx.Response(
            code, json={**healthy_body, "private": "private-test-fixture"}
        )

    with TestClient(create_app(transport=httpx.MockTransport(upstream))) as client:
        assert client.get("/health").json() == {"status": "ok"}
        assert not calls  # Liveness independe da consulta central.
        for _ in range(2):
            response = client.get("/local/status")
            assert_safe_status(response)
            assert "private-test-fixture" not in response.text
        assert len(calls) == 2  # Uma consulta por pedido, sem cache/polling.


@pytest.mark.parametrize("error_type", [httpx.ReadTimeout, httpx.ConnectError])
def test_local_route_handles_network_failures_without_exposing_details(
    configured_environment, error_type
):
    def upstream(request):
        raise error_type("private-test-fixture", request=request)

    with TestClient(create_app(transport=httpx.MockTransport(upstream))) as client:
        response = client.get("/local/status")
        assert_safe_status(response)
        assert "private-test-fixture" not in response.text
        assert client.get("/health").json() == {"status": "ok"}


def test_invalid_configuration_keeps_process_alive(monkeypatch):
    monkeypatch.setenv("BINGO_BACKEND_TIMEOUT_SECONDS", "nan")
    with TestClient(create_app()) as client:
        assert client.get("/health").json() == {"status": "ok"}
        assert_safe_status(client.get("/local/status"))


def test_http_transport_is_closed_on_shutdown(configured_environment, healthy_body):
    class RecordingTransport(httpx.MockTransport):
        closed = False

        async def aclose(self):
            self.closed = True

    transport = RecordingTransport(lambda _: httpx.Response(200, json=healthy_body))
    with TestClient(create_app(transport=transport)) as client:
        assert_safe_status(client.get("/local/status"))
        assert not transport.closed
    assert transport.closed


def test_repeated_status_queries_do_not_unlock_deposits(client):
    for _ in range(3):
        assert_safe_status(client.get("/local/status"))


def test_caller_cannot_override_local_availability(client):
    response = client.get(
        "/local/status?status=ONLINE&can_start_deposit=true",
        headers={"X-Machine-Id": "caller", "X-Api-Key": "caller-fixture"},
    )

    assert_safe_status(response)


@pytest.mark.parametrize("path", ["/health", "/local/status"])
def test_routes_are_read_only(client, path):
    assert client.post(path, json={"can_start_deposit": True}).status_code == 405


@pytest.mark.parametrize(
    "path",
    ["/v1/deposits", "/bingo/deposits", "/vision/analyze"],
)
def test_operational_routes_are_not_exposed(client, path):
    assert client.post(path, json={}).status_code == 404
