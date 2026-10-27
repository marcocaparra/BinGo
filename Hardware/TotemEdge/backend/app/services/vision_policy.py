"""Heurísticas de labels reutilizadas de Software/apps/totem_ui/edge_vision_service.py.

Origem: PR #48 / develop 9f385ab. Apenas política pura, sem HTTP ou credenciais.
IDs visuais não são categorias oficiais nem autorização de descarte.
"""

CATEGORY_LABELS = {
    "battery": {"battery", "alkaline battery", "lithium battery", "battery charger"},
    "cable": {
        "cable",
        "usb cable",
        "electrical wiring",
        "wire",
        "wiring",
        "power cord",
    },
    "phone": {"mobile phone", "cell phone", "smartphone", "telephone"},
    "small": {
        "computer mouse",
        "mouse",
        "headphones",
        "headset",
        "earphones",
        "printed circuit board",
        "computer hardware",
        "electronic component",
    },
}
ELECTRONIC_LABELS = {
    "electronics",
    "hardware",
    "computer",
    "computer hardware",
    "electronic device",
    "electrical device",
    "printed circuit board",
    "mobile phone",
    "cell phone",
    "smartphone",
    "battery",
    "cable",
    "computer mouse",
    "headphones",
    "headset",
}
SECONDARY_HINT_LABELS = {
    "battery": {"can", "tin", "cylinder"},
    "cable": {"adapter", "plug"},
    "small": {"remote control", "calculator", "lightbulb", "light bulb"},
}
NON_ELECTRONIC_CONTEXT_LABELS = {
    "beverage",
    "pop bottle",
    "soda",
    "drink",
    "water bottle",
    "plastic bottle",
}
PRESENTATION_LABELS = {"hand", "finger"}
VERTICAL_BATTERY_HINT_LABELS = {
    "marker",
    "crayon",
    "dynamite",
    "lighter",
    "can",
    "tin",
    "cylinder",
}


def classify_labels(labels: list[dict], fallback_threshold: float = 0.75) -> dict:
    normalized = {
        str(label.get("Name", "")).strip().lower(): float(label.get("Confidence", 0))
        / 100
        for label in labels
        if label.get("Name")
    }
    electronic_confidence = max(
        (
            confidence
            for name, confidence in normalized.items()
            if name in ELECTRONIC_LABELS
        ),
        default=0.0,
    )
    category_scores = {
        item_id: max((normalized.get(name, 0.0) for name in names), default=0.0)
        for item_id, names in CATEGORY_LABELS.items()
    }
    candidates = [
        item_id
        for item_id, score in sorted(
            category_scores.items(), key=lambda pair: pair[1], reverse=True
        )
        if score > 0
    ]
    secondary_scores = {
        item_id: max((normalized.get(name, 0.0) for name in names), default=0.0)
        for item_id, names in SECONDARY_HINT_LABELS.items()
    }
    secondary_candidates = [
        item_id
        for item_id, score in sorted(
            secondary_scores.items(), key=lambda pair: pair[1], reverse=True
        )
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
        ordered_candidates = list(dict.fromkeys([*extra_candidates, *candidates])) or [
            "unknown"
        ]
        return {
            "status": "needs-secondary",
            "itemId": None,
            "candidateIds": ordered_candidates,
            "confidence": round(confidence, 4),
            "origin": "AWS_REKOGNITION",
        }

    if electronic_confidence == 0:
        if non_electronic_context >= 0.5:
            return {
                "status": "rejected",
                "itemId": None,
                "candidateIds": [],
                "confidence": 0.0,
                "origin": "AWS_REKOGNITION",
            }
        if secondary_candidates:
            return secondary_result(
                secondary_candidates, max(secondary_scores.values())
            )
        if presentation_confidence >= 0.7:
            presented_candidates = ["battery"] if vertical_battery_hint >= 0.5 else []
            return secondary_result(presented_candidates, presentation_confidence)
        return {
            "status": "rejected",
            "itemId": None,
            "candidateIds": [],
            "confidence": 0.0,
            "origin": "AWS_REKOGNITION",
        }

    item_id = candidates[0] if candidates else "unknown"
    confidence = max(electronic_confidence, category_scores.get(item_id, 0.0))
    if item_id == "unknown":
        return secondary_result(secondary_candidates, confidence)
    if secondary_candidates and item_id not in secondary_candidates:
        return secondary_result(secondary_candidates, confidence)
    if confidence < fallback_threshold:
        return secondary_result([], confidence)

    return {
        "status": "recognized",
        "itemId": item_id,
        "candidateIds": candidates,
        "confidence": round(confidence, 4),
        "origin": "AWS_REKOGNITION",
    }
