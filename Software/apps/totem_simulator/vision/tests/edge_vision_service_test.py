import importlib.util
import json
import pathlib
import unittest
from unittest import mock

MODULE_PATH = pathlib.Path(__file__).parents[1] / "edge_vision_service.py"
SPEC = importlib.util.spec_from_file_location("edge_vision_service", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VisionClassificationTests(unittest.TestCase):
    def test_specific_electronic_category_is_selected(self):
        result = MODULE.classify_labels([
            {"Name": "Electronics", "Confidence": 100},
            {"Name": "Printed Circuit Board", "Confidence": 92},
        ])
        self.assertEqual(result["status"], "recognized")
        self.assertEqual(result["itemId"], "small")

    def test_non_electronic_item_is_rejected(self):
        result = MODULE.classify_labels([{"Name": "Dog", "Confidence": 99}])
        self.assertEqual(result["status"], "rejected")
        self.assertIsNone(result["itemId"])

    def test_uncertain_electronic_requests_secondary_analysis(self):
        result = MODULE.classify_labels([{"Name": "Cable", "Confidence": 62}], fallback_threshold=0.75)
        self.assertEqual(result["status"], "needs-secondary")
        self.assertEqual(result["candidateIds"], ["cable"])

    def test_generic_electronics_requests_secondary_analysis(self):
        result = MODULE.classify_labels([
            {"Name": "Electronics", "Confidence": 99},
            {"Name": "Adapter", "Confidence": 96},
        ])
        self.assertEqual(result["status"], "needs-secondary")
        self.assertEqual(result["candidateIds"], ["cable"])

    def test_conflicting_remote_and_phone_labels_request_secondary_analysis(self):
        result = MODULE.classify_labels([
            {"Name": "Electronics", "Confidence": 99},
            {"Name": "Mobile Phone", "Confidence": 98},
            {"Name": "Remote Control", "Confidence": 95},
        ])
        self.assertEqual(result["status"], "needs-secondary")
        self.assertEqual(result["candidateIds"], ["small", "phone"])

    def test_battery_shaped_object_is_not_silently_rejected(self):
        result = MODULE.classify_labels([
            {"Name": "Can", "Confidence": 90},
            {"Name": "Cylinder", "Confidence": 72},
        ])
        self.assertEqual(result["status"], "needs-secondary")
        self.assertEqual(result["candidateIds"], ["battery"])

    def test_bottles_are_not_escalated_as_lightbulbs(self):
        result = MODULE.classify_labels([
            {"Name": "Plastic", "Confidence": 99},
            {"Name": "Beverage", "Confidence": 91},
            {"Name": "Bottle", "Confidence": 88},
            {"Name": "Lightbulb", "Confidence": 56},
        ])
        self.assertEqual(result["status"], "rejected")
        self.assertEqual(result["candidateIds"], [])

    def test_item_presented_in_hand_gets_secondary_review(self):
        result = MODULE.classify_labels([
            {"Name": "Hand", "Confidence": 94},
            {"Name": "Finger", "Confidence": 91},
            {"Name": "Object", "Confidence": 58},
        ])
        self.assertEqual(result["status"], "needs-secondary")
        self.assertEqual(result["candidateIds"], ["unknown"])

    def test_vertical_battery_shape_is_a_secondary_hint_only(self):
        result = MODULE.classify_labels([
            {"Name": "Hand", "Confidence": 94},
            {"Name": "Marker", "Confidence": 58},
            {"Name": "Crayon", "Confidence": 56},
        ])
        self.assertEqual(result["status"], "needs-secondary")
        self.assertIsNone(result["itemId"])
        self.assertEqual(result["candidateIds"], ["battery"])

    def test_gemini_decision_is_normalized(self):
        result = MODULE.normalize_gemini_decision(
            {"decision": "battery", "confidence": 0.97},
            ["battery", "small"],
        )
        self.assertEqual(result["status"], "recognized")
        self.assertEqual(result["itemId"], "battery")
        self.assertEqual(result["origin"], "GEMINI_FALLBACK")
        self.assertEqual(result["candidateIds"], ["battery", "small"])

    def test_gemini_can_reject_an_unsafe_or_unrelated_item(self):
        result = MODULE.normalize_gemini_decision(
            {"decision": "rejected", "confidence": 0.91},
            ["unknown"],
        )
        self.assertEqual(result["status"], "rejected")
        self.assertIsNone(result["itemId"])
        self.assertEqual(result["origin"], "GEMINI_FALLBACK")

    def test_gemini_request_sends_image_and_structured_schema(self):
        response_payload = {
            "candidates": [{"content": {"parts": [{"text": '{"decision":"cable","confidence":0.96}'}]}}],
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, *_args):
                return json.dumps(response_payload).encode("utf-8")

        with mock.patch.dict(MODULE.os.environ, {"GEMINI_API_KEY": "test-key"}, clear=False):
            with mock.patch.object(MODULE, "urlopen", return_value=FakeResponse()) as mocked_open:
                result = MODULE.analyze_image_with_gemini(b"frame", "image/jpeg", ["cable"])

        request = mocked_open.call_args.args[0]
        self.assertIn("models/gemini-flash-lite-latest:generateContent", request.full_url)
        request_payload = json.loads(request.data)
        image_part = request_payload["contents"][0]["parts"][1]["inline_data"]
        self.assertEqual(image_part, {"mime_type": "image/jpeg", "data": "ZnJhbWU="})
        self.assertEqual(request_payload["generationConfig"]["responseMimeType"], "application/json")
        self.assertEqual(request_payload["generationConfig"]["thinkingConfig"], {"thinkingLevel": "minimal"})
        self.assertEqual(result["itemId"], "cable")
        self.assertEqual(result["origin"], "GEMINI_FALLBACK")

    def test_gemini_retries_one_transient_unavailable_response(self):
        response_payload = {
            "candidates": [{"content": {"parts": [{"text": '{"decision":"battery","confidence":0.94}'}]}}],
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, *_args):
                return json.dumps(response_payload).encode("utf-8")

        unavailable = MODULE.HTTPError("https://example.test", 503, "busy", {}, None)
        environment = {
            "GEMINI_API_KEY": "test-key",
            "BINGO_GEMINI_TRANSIENT_RETRIES": "1",
        }
        with mock.patch.dict(MODULE.os.environ, environment, clear=False):
            with mock.patch.object(MODULE.time, "sleep") as mocked_sleep:
                with mock.patch.object(MODULE, "urlopen", side_effect=[unavailable, FakeResponse()]) as mocked_open:
                    result = MODULE.analyze_image_with_gemini(b"frame", "image/jpeg", ["battery"])

        self.assertEqual(mocked_open.call_count, 2)
        mocked_sleep.assert_called_once_with(1)
        self.assertEqual(result["itemId"], "battery")

    def test_gemini_retries_one_timeout(self):
        response_payload = {
            "candidates": [{"content": {"parts": [{"text": '{"decision":"battery","confidence":0.98}'}]}}],
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, *_args):
                return json.dumps(response_payload).encode("utf-8")

        environment = {
            "GEMINI_API_KEY": "test-key",
            "BINGO_GEMINI_TRANSIENT_RETRIES": "1",
        }
        with mock.patch.dict(MODULE.os.environ, environment, clear=False):
            with mock.patch.object(MODULE.time, "sleep") as mocked_sleep:
                with mock.patch.object(MODULE, "urlopen", side_effect=[TimeoutError(), FakeResponse()]) as mocked_open:
                    result = MODULE.analyze_image_with_gemini(b"frame", "image/jpeg", ["battery"])

        self.assertEqual(mocked_open.call_count, 2)
        mocked_sleep.assert_called_once_with(1)
        self.assertEqual(result["itemId"], "battery")

    def test_gemini_takes_over_when_rekognition_fails(self):
        gemini_result = {
            "status": "recognized",
            "itemId": "battery",
            "candidateIds": ["battery"],
            "confidence": 0.95,
            "origin": "GEMINI_FALLBACK",
        }
        with mock.patch.dict(MODULE.os.environ, {"GEMINI_API_KEY": "test-key"}, clear=False):
            with mock.patch.object(MODULE, "analyze_image", side_effect=RuntimeError("aws down")):
                with mock.patch.object(MODULE, "analyze_image_with_gemini", return_value=gemini_result):
                    result = MODULE.analyze_primary_with_fallback(b"frame", "image/jpeg")
        self.assertEqual(result["itemId"], "battery")
        self.assertEqual(result["origin"], "GEMINI_FALLBACK")
        self.assertEqual(result["fallbackReason"], "primary_provider_error")


if __name__ == "__main__":
    unittest.main()
