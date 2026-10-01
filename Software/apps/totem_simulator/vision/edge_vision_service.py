"""Lightweight, memory-only vision bridge for the BinGo kiosk.

The browser sends a single captured frame to this loopback service. The service
calls Rekognition first and Gemini only for ambiguous results, returns a
normalized decision and immediately releases the frame. It never writes images
to disk.
"""

from __future__ import annotations

import base64
import binascii
import hmac
import json
import os
import socket
import time
from pathlib import Path
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

MAX_IMAGE_BYTES = 5 * 1024 * 1024
SUPPORTED_IMAGE_TYPES = {"image/jpeg", "image/png"}

# Credentials stay inside this loopback process. No Supabase privileged key is
# needed here: Edge Functions authenticate the machine and own DB privileges.
BINGO_ROUTES = {
    ("GET", "/bingo/health"): ("health-v1", ()),
    ("GET", "/bingo/context"): ("totem-context-v1", ()),
    ("GET", "/bingo/rankings"): ("totem-rankings-v1", ()),
    ("POST", "/bingo/student-summary"): ("totem-student-summary-v1", ("student_id",)),
    ("POST", "/bingo/student-pin"): ("totem-student-pin-v1", ("class_id", "student_id", "pin")),
    ("POST", "/bingo/deposits"): ("register-deposit-v1", (
        "event_id", "class_id", "student_id", "is_valid", "detected_type",
        "waste_category_code", "category_source")),
}


# Cloud serves only this explicit frontend allowlist, never an application directory.
FRONTEND_ROOT = Path(__file__).resolve().parents[1]
STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/backend_client.js": ("backend_client.js", "text/javascript; charset=utf-8"),
    "/runtime.js": ("runtime.js", "text/javascript; charset=utf-8"),
    "/vision/vision_provider.js": ("vision/vision_provider.js", "text/javascript; charset=utf-8"),
}


def runtime_mode() -> str:
    mode = os.getenv("BINGO_RUNTIME_MODE", "local")
    if mode not in {"local", "cloud"}:
        raise ValueError("BINGO_RUNTIME_MODE must be local or cloud")
    return mode


def demo_credentials() -> tuple[str, str]:
    return os.getenv("BINGO_DEMO_USERNAME", ""), os.getenv("BINGO_DEMO_PASSWORD", "")


def listen_address() -> tuple[str, int]:
    if runtime_mode() == "cloud":
        username, password = demo_credentials()
        if not username or not password or ":" in username:
            raise ValueError("Cloud demo credentials must be configured")
        host, port = "0.0.0.0", int(os.environ["PORT"])
    else:
        host = os.getenv("BINGO_VISION_HOST", "127.0.0.1")
        if host not in {"127.0.0.1", "localhost"}:
            raise ValueError("This trusted service must bind to loopback only")
        port = int(os.getenv("BINGO_VISION_PORT", "8765"))
    if not 1 <= port <= 65535:
        raise ValueError("Invalid listening port")
    return host, port


def forward_bingo(method: str, path: str, payload: dict | None) -> tuple[int, dict]:
    function, _ = BINGO_ROUTES[(method, path)]
    url = os.getenv("BINGO_SUPABASE_URL", "").rstrip("/")
    machine_id = os.getenv("BINGO_MACHINE_ID", "")
    key = os.getenv("BINGO_MACHINE_API_KEY", "")
    parsed = urlparse(url)
    if (not machine_id or not key or parsed.username or parsed.password or
            parsed.query or parsed.fragment or parsed.path not in ("", "/") or
            not parsed.hostname or not (parsed.scheme == "https" or
                parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"})):
        return 503, {"error": {"code": "BACKEND_NOT_CONFIGURED", "message": "Configure o backend no serviço local."}}
    request = Request(f"{url}/functions/v1/{function}",
        data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        headers={"Content-Type": "application/json", "X-Machine-Id": machine_id, "X-Api-Key": key},
        method=method)
    try:
        try:
            response = urlopen(request, timeout=float(os.getenv("BINGO_BACKEND_TIMEOUT_SECONDS", "15")))
        except HTTPError as error:
            response = error
        with response:
            status = response.code
            body = json.loads(response.read(8 * 1024 * 1024))
        if not isinstance(body, dict):
            raise ValueError("Invalid upstream body")
        return status, body
    except (URLError, TimeoutError, socket.timeout, OSError):
        return 504, {"error": {"code": "BACKEND_RESULT_UNKNOWN", "message": "Backend indisponível ou sem resposta. Preserve o evento para retry."}}
    except (ValueError, TypeError):
        return 502, {"error": {"code": "INVALID_BACKEND_RESPONSE", "message": "Resposta inválida do backend."}}

CATEGORY_LABELS = {
    "battery": {"battery", "alkaline battery", "lithium battery", "battery charger"},
    "cable": {"cable", "usb cable", "electrical wiring", "wire", "wiring", "power cord"},
    "phone": {"mobile phone", "cell phone", "smartphone", "telephone"},
    "small": {
        "computer mouse", "mouse", "headphones", "headset", "earphones",
        "printed circuit board", "computer hardware", "electronic component",
    },
}
ELECTRONIC_LABELS = {
    "electronics", "hardware", "computer", "computer hardware", "electronic device",
    "electrical device", "printed circuit board", "mobile phone", "cell phone",
    "smartphone", "battery", "cable", "computer mouse", "headphones", "headset",
}
SECONDARY_HINT_LABELS = {
    "battery": {"can", "tin", "cylinder"},
    "cable": {"adapter", "plug"},
    "small": {"remote control", "calculator", "lightbulb", "light bulb"},
}
NON_ELECTRONIC_CONTEXT_LABELS = {
    "beverage", "pop bottle", "soda", "drink", "water bottle", "plastic bottle",
}
PRESENTATION_LABELS = {"hand", "finger"}
VERTICAL_BATTERY_HINT_LABELS = {"marker", "crayon", "dynamite", "lighter", "can", "tin", "cylinder"}


def classify_labels(labels: list[dict], fallback_threshold: float = 0.75) -> dict:
    normalized = {
        str(label.get("Name", "")).strip().lower(): float(label.get("Confidence", 0)) / 100
        for label in labels
        if label.get("Name")
    }
    electronic_confidence = max(
        (confidence for name, confidence in normalized.items() if name in ELECTRONIC_LABELS),
        default=0.0,
    )
    category_scores = {
        item_id: max((normalized.get(name, 0.0) for name in names), default=0.0)
        for item_id, names in CATEGORY_LABELS.items()
    }
    candidates = [item_id for item_id, score in sorted(category_scores.items(), key=lambda pair: pair[1], reverse=True) if score > 0]
    secondary_scores = {
        item_id: max((normalized.get(name, 0.0) for name in names), default=0.0)
        for item_id, names in SECONDARY_HINT_LABELS.items()
    }
    secondary_candidates = [
        item_id
        for item_id, score in sorted(secondary_scores.items(), key=lambda pair: pair[1], reverse=True)
        if score > 0
    ]
    non_electronic_context = max(
        (normalized.get(name, 0.0) for name in NON_ELECTRONIC_CONTEXT_LABELS),
        default=0.0,
    )
    presentation_confidence = max(
        (normalized.get(name, 0.0) for name in PRESENTATION_LABELS),
        default=0.0,
    )
    vertical_battery_hint = max(
        (normalized.get(name, 0.0) for name in VERTICAL_BATTERY_HINT_LABELS),
        default=0.0,
    )

    def secondary_result(extra_candidates: list[str], confidence: float) -> dict:
        ordered_candidates = list(dict.fromkeys([*extra_candidates, *candidates])) or ["unknown"]
        return {
            "status": "needs-secondary",
            "itemId": None,
            "candidateIds": ordered_candidates,
            "confidence": round(confidence, 4),
            "origin": "AWS_REKOGNITION",
        }

    if electronic_confidence == 0:
        if non_electronic_context >= 0.5:
            return {"status": "rejected", "itemId": None, "candidateIds": [], "confidence": 0.0, "origin": "AWS_REKOGNITION"}
        if secondary_candidates:
            return secondary_result(secondary_candidates, max(secondary_scores.values()))
        if presentation_confidence >= 0.7:
            presented_candidates = ["battery"] if vertical_battery_hint >= 0.5 else []
            return secondary_result(presented_candidates, presentation_confidence)
        return {"status": "rejected", "itemId": None, "candidateIds": [], "confidence": 0.0, "origin": "AWS_REKOGNITION"}

    item_id = candidates[0] if candidates else "unknown"
    confidence = max(electronic_confidence, category_scores.get(item_id, 0.0))
    if item_id == "unknown":
        return secondary_result(secondary_candidates, confidence)
    if secondary_candidates and item_id not in secondary_candidates:
        return secondary_result(secondary_candidates, confidence)
    if confidence < fallback_threshold:
        return secondary_result([], confidence)

    return {"status": "recognized", "itemId": item_id, "candidateIds": candidates, "confidence": round(confidence, 4), "origin": "AWS_REKOGNITION"}


def analyze_image(image_bytes: bytes) -> dict:
    try:
        import boto3
    except ImportError as error:
        raise RuntimeError("boto3 is required: pip install -r vision/requirements.txt") from error

    client = boto3.client("rekognition", region_name=os.getenv("AWS_REGION", "sa-east-1"))
    response = client.detect_labels(
        Image={"Bytes": image_bytes},
        MaxLabels=int(os.getenv("AWS_REKOGNITION_MAX_LABELS", "20")),
        MinConfidence=float(os.getenv("AWS_REKOGNITION_MIN_CONFIDENCE", "55")),
    )
    result = classify_labels(response.get("Labels", []), float(os.getenv("BINGO_VISION_FALLBACK_THRESHOLD", "0.75")))
    result["labels"] = [
        {"name": label.get("Name"), "confidence": round(float(label.get("Confidence", 0)) / 100, 4)}
        for label in response.get("Labels", [])[:10]
    ]
    return result


def normalize_gemini_decision(payload: dict, prior_candidates: list[str]) -> dict:
    decision = str(payload.get("decision", "")).strip().lower()
    allowed = {"battery", "cable", "phone", "small", "rejected"}
    if decision not in allowed:
        raise ValueError("Gemini returned an invalid decision")
    try:
        confidence = max(0.0, min(1.0, float(payload.get("confidence", 0))))
    except (TypeError, ValueError) as error:
        raise ValueError("Gemini returned an invalid confidence") from error
    candidates = list(dict.fromkeys([decision, *prior_candidates])) if decision != "rejected" else prior_candidates
    return {
        "status": "rejected" if decision == "rejected" else "recognized",
        "itemId": None if decision == "rejected" else decision,
        "candidateIds": candidates,
        "confidence": round(confidence, 4),
        "origin": "GEMINI_FALLBACK",
    }


def analyze_image_with_gemini(image_bytes: bytes, content_type: str, prior_candidates: list[str]) -> dict:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured")
    model = os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest")
    prompt = (
        "Classifique o unico objeto que a pessoa apresenta para o Totem BinGo. "
        "Observe formato, escala em relacao a mao, conectores e inscricoes visiveis; "
        "nao trate a mao, a pessoa nem o ambiente como o objeto principal. "
        "Use battery para pilha ou bateria; cable para cabo, fio, carregador ou adaptador; "
        "phone para celular ou smartphone; small para outro eletronico pequeno autorizado, "
        "como mouse, fone, teclado, controle, calculadora, placa ou lampada; e rejected para "
        "objeto nao eletronico, brinquedo, item grande, item perigoso, imagem vazia ou quando "
        "nao for possivel confirmar. Para pilhas, procure corpo cilindrico pequeno ou formato "
        "de bateria e indicacoes como AA, AAA, alcalina, lithium, volts ou marca de pilha. "
        f"Candidatos sugeridos pelo Rekognition: {', '.join(prior_candidates) or 'nenhum'}. "
        "Os candidatos sao apenas pistas e podem estar errados. A seguranca e mais importante "
        "que aceitar o item."
    )
    body = {
        "contents": [{
            "parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": content_type, "data": base64.b64encode(image_bytes).decode("ascii")}},
            ],
        }],
        "generationConfig": {
            "temperature": 0,
            "thinkingConfig": {"thinkingLevel": "minimal"},
            "responseMimeType": "application/json",
            "responseSchema": {
                "type": "object",
                "properties": {
                    "decision": {"type": "string", "enum": ["battery", "cable", "phone", "small", "rejected"]},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                },
                "required": ["decision", "confidence"],
            },
        },
    }
    endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    request = Request(
        endpoint,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        method="POST",
    )
    timeout = float(os.getenv("BINGO_GEMINI_TIMEOUT_SECONDS", "10"))
    retries = max(0, int(os.getenv("BINGO_GEMINI_TRANSIENT_RETRIES", "1")))
    response_body = None
    for attempt in range(retries + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                response_body = json.load(response)
            break
        except HTTPError as error:
            if error.code not in (429, 503) or attempt >= retries:
                raise RuntimeError("Gemini request failed") from error
            time.sleep(min(2 ** attempt, 2))
        except (URLError, TimeoutError) as error:
            if attempt >= retries:
                raise RuntimeError("Gemini request failed") from error
            time.sleep(min(2 ** attempt, 2))
    if response_body is None:
        raise RuntimeError("Gemini request failed")
    try:
        response_text = response_body["candidates"][0]["content"]["parts"][0]["text"]
        decision_payload = json.loads(response_text)
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as error:
        raise RuntimeError("Gemini returned an invalid response") from error
    return normalize_gemini_decision(decision_payload, prior_candidates)


def analyze_primary_with_fallback(image_bytes: bytes, content_type: str) -> dict:
    try:
        return analyze_image(image_bytes)
    except Exception:
        if not os.getenv("GEMINI_API_KEY", "").strip():
            raise
        result = analyze_image_with_gemini(image_bytes, content_type, [])
        result["fallbackReason"] = "primary_provider_error"
        return result


class VisionHandler(BaseHTTPRequestHandler):
    server_version = "BinGoEdgeVision/1.0"

    def _origin(self) -> str | None:
        origin = self.headers.get("Origin")
        if runtime_mode() == "cloud" or not origin:
            return None
        parsed = urlparse(origin)
        allowed = {item.strip() for item in os.getenv("BINGO_ALLOWED_ORIGINS", "").split(",") if item.strip()}
        if (parsed.scheme in {"http", "https"} and parsed.hostname in {"127.0.0.1", "localhost"}
                and not parsed.username and not parsed.password and (not allowed or origin in allowed)):
            return origin
        return None

    def _send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        origin = self._origin()
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(body)

    def _cloud_authorized(self) -> bool:
        username, password = demo_credentials()
        if not username or not password or ":" in username:
            self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "demo_not_configured"})
            return False
        header = self.headers.get("Authorization", "")
        try:
            scheme, encoded = header.split(" ", 1)
            if scheme.lower() != "basic":
                raise ValueError()
            supplied_user, supplied_password = base64.b64decode(encoded, validate=True).split(b":", 1)
            valid_user = hmac.compare_digest(supplied_user, username.encode("utf-8"))
            valid_password = hmac.compare_digest(supplied_password, password.encode("utf-8"))
            valid = valid_user & valid_password
        except (ValueError, binascii.Error):
            valid = False
        if not valid:
            self.send_response(HTTPStatus.UNAUTHORIZED)
            self.send_header("WWW-Authenticate", 'Basic realm="BinGo demo", charset="UTF-8"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False
        # Cloud Run terminates TLS. No CORS is opened: operational requests must
        # originate from this Host, using the proxy's http/https scheme.
        origin = self.headers.get("Origin")
        scheme = self.headers.get("X-Forwarded-Proto", "http")
        if origin and (scheme not in {"http", "https"} or
                       origin != f"{scheme}://{self.headers.get('Host', '')}"):
            self._send_json(HTTPStatus.FORBIDDEN, {"error": "same_origin_required"})
            return False
        if self.headers.get("Sec-Fetch-Site") in {"cross-site", "same-site"}:
            self._send_json(HTTPStatus.FORBIDDEN, {"error": "same_origin_required"})
            return False
        return True

    def _static_frontend(self) -> None:
        path = urlparse(self.path).path
        if "%" in path or ".." in path or "\\" in path:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        if path == "/sample_library.js":
            # Do not publish the unverified sample catalog or its images.
            body = b"window.BinGoSamples = Object.freeze([]);\n"
            mime = "text/javascript; charset=utf-8"
        elif path in STATIC_FILES:
            filename, mime = STATIC_FILES[path]
            body = (FRONTEND_ROOT / filename).read_bytes()
            if path == "/runtime.js":
                # Only a public runtime flag is emitted, never environment vars.
                body = b'globalThis.BinGoRuntimeMode = "cloud";\n' + body
        else:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _local_request(self) -> bool:
        if runtime_mode() == "cloud":
            return self._cloud_authorized()
        host = urlparse("http://" + self.headers.get("Host", "")).hostname
        if host not in {"127.0.0.1", "localhost"} or (self.headers.get("Origin") and not self._origin()):
            self._send_json(HTTPStatus.FORBIDDEN, {"error": "local_origin_required"})
            return False
        return True

    def _bingo_request(self, method: str) -> None:
        parsed = urlparse(self.path)
        route = BINGO_ROUTES.get((method, parsed.path))
        if not route or parsed.query:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        payload = None
        if method == "POST":
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 4096 or self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                    raise ValueError()
                payload = json.loads(self.rfile.read(length))
                if not isinstance(payload, dict) or set(payload) != set(route[1]):
                    raise ValueError()
            except (ValueError, TypeError):
                self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": {"code": "INVALID_LOCAL_CONTRACT", "message": "Payload inválido."}})
                return
        status, body = forward_bingo(method, parsed.path, payload)
        self._send_json(status, body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        if not self._local_request():
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        origin = self._origin()
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-BinGo-Edge-Key")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Vary", "Origin")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if runtime_mode() == "cloud" and self.path == "/healthz":
            self._send_json(HTTPStatus.OK, {"status": "ok"})
            return
        if not self._local_request():
            return
        if urlparse(self.path).path.startswith("/bingo/"):
            self._bingo_request("GET")
            return
        if urlparse(self.path).path == "/health":
            gemini_configured = bool(os.getenv("GEMINI_API_KEY", "").strip())
            self._send_json(HTTPStatus.OK, {
                "status": "ok",
                "service": "bingo-edge-vision",
                "primaryProvider": "AWS_REKOGNITION",
                "secondaryProvider": "GEMINI_FALLBACK" if gemini_configured else "MANUAL_REVIEW",
                "geminiModel": os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest") if gemini_configured else None,
            })
            return
        if runtime_mode() == "cloud":
            self._static_frontend()
            return
        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._local_request():
            return
        parsed = urlparse(self.path)
        if parsed.path.startswith("/bingo/"):
            self._bingo_request("POST")
            return
        if parsed.path != "/vision/analyze":
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        expected_key = os.getenv("BINGO_EDGE_API_KEY")
        if expected_key and self.headers.get("X-BinGo-Edge-Key") != expected_key:
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "invalid_edge_key"})
            return
        query = parse_qs(parsed.query)
        stage = query.get("stage", ["primary"])[0]
        if stage not in {"primary", "secondary"}:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_vision_stage"})
            return
        content_type = self.headers.get("Content-Type", "").split(";", 1)[0].lower()
        if content_type not in SUPPORTED_IMAGE_TYPES:
            self._send_json(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, {"error": "unsupported_image_type"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_IMAGE_BYTES:
            self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "invalid_image_size"})
            return
        image_bytes = self.rfile.read(length)
        try:
            if stage == "secondary":
                if not os.getenv("GEMINI_API_KEY", "").strip():
                    self._send_json(HTTPStatus.NOT_IMPLEMENTED, {"error": "secondary_provider_unavailable"})
                    return
                candidates = [
                    item
                    for item in query.get("candidates", [""])[0].split(",")
                    if item in CATEGORY_LABELS or item == "unknown"
                ]
                result = analyze_image_with_gemini(image_bytes, content_type, candidates)
            else:
                result = analyze_primary_with_fallback(image_bytes, content_type)
            self._send_json(HTTPStatus.OK, result)
        except Exception as error:  # Keep SDK details out of the browser response.
            print(f"Vision analysis failed: {type(error).__name__}")
            self._send_json(HTTPStatus.BAD_GATEWAY, {
                "error": "vision_provider_failed",
                "provider": "GEMINI_FALLBACK" if stage == "secondary" else "VISION_CASCADE",
            })

    def log_message(self, format: str, *args) -> None:
        # Never log query strings or request bodies (in particular student PIN).
        path = urlparse(self.path).path
        allowed_paths = {route[1] for route in BINGO_ROUTES} | {"/health", "/vision/analyze"}
        route = path if path in allowed_paths else "/unknown"
        status = args[1] if len(args) > 1 else "error"
        print(f"[edge-vision] {self.command} {route} {status}")


def main() -> None:
    host, port = listen_address()
    server = ThreadingHTTPServer((host, port), VisionHandler)
    print(f"BinGo Edge Vision listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
