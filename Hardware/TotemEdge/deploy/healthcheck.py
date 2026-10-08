"""Local process health only; no Supabase, readiness or business calls."""

import json
from urllib.request import ProxyHandler, build_opener


def healthy() -> bool:
    try:
        with build_opener(ProxyHandler({})).open(
            "http://127.0.0.1:8000/health", timeout=2
        ) as response:
            return response.status == 200 and json.loads(response.read(128)) == {
                "status": "ok"
            }
    except (OSError, ValueError):
        return False


if __name__ == "__main__":
    raise SystemExit(0 if healthy() else 1)
