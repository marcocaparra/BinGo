import os
import ipaddress
import socket

import pytest


@pytest.fixture(autouse=True)
def loopback_network_only(monkeypatch):
    """Fail closed before DNS/connect; TestClient and mocked transports still work."""
    resolve = socket.getaddrinfo
    connect = socket.socket.connect
    connect_ex = socket.socket.connect_ex

    def permitted(host):
        if host in ("localhost", b"localhost"):
            return
        try:
            if ipaddress.ip_address(host).is_loopback:
                return
        except ValueError:
            pass
        raise OSError("External network is disabled in TotemEdge tests")

    def local_resolve(host, *args, **kwargs):
        if host is not None:
            permitted(host)
        return resolve(host, *args, **kwargs)

    def local_connect(sock, address):
        if sock.family in (socket.AF_INET, socket.AF_INET6):
            permitted(address[0])
        return connect(sock, address)

    def local_connect_ex(sock, address):
        if sock.family in (socket.AF_INET, socket.AF_INET6):
            permitted(address[0])
        return connect_ex(sock, address)

    monkeypatch.setattr(socket, "getaddrinfo", local_resolve)
    monkeypatch.setattr(socket.socket, "connect", local_connect)
    monkeypatch.setattr(socket.socket, "connect_ex", local_connect_ex)


@pytest.fixture(autouse=True)
def clear_supabase_environment(monkeypatch, tmp_path):
    # Nenhum teste pode herdar credenciais reais do processo que executa pytest.
    for name in tuple(os.environ):
        if name.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_")):
            monkeypatch.delenv(name, raising=False)
    for name in (
        "BINGO_SUPABASE_URL",
        "BINGO_MACHINE_ID",
        "BINGO_MACHINE_API_KEY",
        "BINGO_BACKEND_TIMEOUT_SECONDS",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "AWS_REGION",
        "GEMINI_API_KEY",
        "GEMINI_MODEL",
        "BINGO_GEMINI_TIMEOUT_SECONDS",
        "BINGO_GEMINI_TRANSIENT_RETRIES",
    ):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(tmp_path / "totem.sqlite3"))


@pytest.fixture
def configured_environment(monkeypatch):
    config = {
        "BINGO_SUPABASE_URL": "https://backend.example.invalid",
        "BINGO_MACHINE_ID": "00000000-0000-4000-8000-000000000001",
        "BINGO_MACHINE_API_KEY": "private-test-fixture",
        "BINGO_BACKEND_TIMEOUT_SECONDS": "2.5",
    }
    for name, value in config.items():
        monkeypatch.setenv(name, value)
    return config


@pytest.fixture
def healthy_body():
    return {
        "status": "AVAILABLE",
        "can_start_deposit": True,
        "scope": "CENTRAL_BACKEND",
        "checked_at": "2026-10-07T12:00:00.000Z",
    }


@pytest.fixture
def anyio_backend():
    return "asyncio"
