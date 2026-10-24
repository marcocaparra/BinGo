import pytest


@pytest.fixture(autouse=True)
def clear_supabase_environment(monkeypatch, tmp_path):
    # Nenhum teste pode herdar credenciais reais do processo que executa pytest.
    for name in (
        "BINGO_SUPABASE_URL",
        "BINGO_MACHINE_ID",
        "BINGO_MACHINE_API_KEY",
        "BINGO_BACKEND_TIMEOUT_SECONDS",
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
