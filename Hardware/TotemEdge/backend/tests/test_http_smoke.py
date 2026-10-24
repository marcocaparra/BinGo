import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fastapi.testclient import TestClient

from app.main import create_app


def test_real_http_transport_against_loopback_supabase_stub(
    configured_environment, healthy_body, monkeypatch
):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append((self.path, dict(self.headers)))
            body = json.dumps(healthy_body).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setenv("BINGO_SUPABASE_URL", f"http://127.0.0.1:{server.server_port}")
    # Proxies do ambiente não podem capturar credenciais técnicas.
    monkeypatch.setenv("HTTP_PROXY", "http://127.0.0.1:1")
    monkeypatch.setenv("HTTPS_PROXY", "http://127.0.0.1:1")
    monkeypatch.setenv("ALL_PROXY", "http://127.0.0.1:1")
    monkeypatch.setenv("NO_PROXY", "")
    try:
        with TestClient(create_app()) as client:
            assert client.get("/health").json() == {"status": "ok"}
            assert not requests
            response = client.get("/local/status")
            assert response.status_code == 200
            assert response.headers["Cache-Control"] == "no-store"
            assert response.json()["status"] == "OFFLINE"
            assert response.json()["can_start_deposit"] is False
            assert "private-test-fixture" not in response.text
        assert len(requests) == 1
        path, headers = requests[0]
        assert path == "/functions/v1/health-v1"
        assert headers["X-Machine-Id"] == configured_environment["BINGO_MACHINE_ID"]
        assert headers["X-Api-Key"] == configured_environment["BINGO_MACHINE_API_KEY"]
        assert "Authorization" not in headers
        assert "apikey" not in headers
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        assert not thread.is_alive()
