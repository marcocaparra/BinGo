"""Lightweight, memory-only vision bridge for the BinGo kiosk.

The browser sends a single captured frame to this loopback service. The service
calls Rekognition first and Gemini only for ambiguous results, returns a
normalized decision and immediately releases the frame. It never writes images
to disk.
"""

from __future__ import annotations

import base64
import json
import os
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

MAX_IMAGE_BYTES = 5 * 1024 * 1024
SUPPORTED_IMAGE_TYPES = {"image/jpeg", "image/png"}

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
        raise RuntimeError("boto3 is required: pip install -r edge-requirements.txt") from error

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
        if not origin:
            return None
        parsed = urlparse(origin)
        allowed = {item.strip() for item in os.getenv("BINGO_ALLOWED_ORIGINS", "").split(",") if item.strip()}
        if origin in allowed or parsed.hostname in {"127.0.0.1", "localhost"}:
            return origin
        return None

    def _send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        origin = self._origin()
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        origin = self._origin()
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-BinGo-Edge-Key")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Vary", "Origin")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
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
        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
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
            print(f"Vision analysis failed: {type(error).__name__}: {error}")
            self._send_json(HTTPStatus.BAD_GATEWAY, {
                "error": "vision_provider_failed",
                "provider": "GEMINI_FALLBACK" if stage == "secondary" else "VISION_CASCADE",
            })

    def log_message(self, format: str, *args) -> None:
        print(f"[edge-vision] {self.address_string()} {format % args}")


def main() -> None:
    host = os.getenv("BINGO_VISION_HOST", "127.0.0.1")
    port = int(os.getenv("BINGO_VISION_PORT", "8765"))
    server = ThreadingHTTPServer((host, port), VisionHandler)
    print(f"BinGo Edge Vision listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
