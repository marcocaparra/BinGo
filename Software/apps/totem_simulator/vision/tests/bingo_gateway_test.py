import importlib.util
import io
import json
import os
import pathlib
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from unittest import mock

SPEC = importlib.util.spec_from_file_location('gateway', pathlib.Path(__file__).parents[1] / 'edge_vision_service.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CONFIG = {'BINGO_SUPABASE_URL': 'http://127.0.0.1:54321', 'BINGO_MACHINE_ID': 'machine-fixture', 'BINGO_MACHINE_API_KEY': 'private-fixture'}


class FakeResponse(io.BytesIO):
    code = 200


class ForwardingTests(unittest.TestCase):
    def test_identity_is_added_only_server_side(self):
        def upstream(request, timeout):
            self.assertEqual(request.full_url, 'http://127.0.0.1:54321/functions/v1/totem-student-pin-v1')
            self.assertEqual(request.get_header('X-machine-id'), 'machine-fixture')
            self.assertEqual(request.get_header('X-api-key'), 'private-fixture')
            self.assertEqual(json.loads(request.data), {'class_id': 'class', 'student_id': 'student', 'pin': '1234'})
            return FakeResponse(b'{"confirmed":true,"student":{"id":"student"}}')
        with mock.patch.dict(os.environ, CONFIG, clear=True), mock.patch.object(MODULE, 'urlopen', side_effect=upstream):
            status, body = MODULE.forward_bingo('POST', '/bingo/student-pin', {'class_id': 'class', 'student_id': 'student', 'pin': '1234'})
        self.assertEqual(status, 200)
        self.assertNotIn('private-fixture', json.dumps(body))
        self.assertNotIn('1234', json.dumps(body))

    def test_missing_configuration_and_unsafe_urls_are_rejected(self):
        for config in [{}, {**CONFIG, 'BINGO_SUPABASE_URL': 'http://remote.example'}, {**CONFIG, 'BINGO_SUPABASE_URL': 'https://secret@remote.example'}]:
            with mock.patch.dict(os.environ, config, clear=True), mock.patch.object(MODULE, 'urlopen') as upstream:
                self.assertEqual(MODULE.forward_bingo('GET', '/bingo/health', None)[0], 503)
                upstream.assert_not_called()

    def test_upstream_status_preserved_network_and_invalid_json_sanitized(self):
        for code in [401, 404, 409, 422, 500, 503]:
            failure = HTTPError('http://localhost', code, 'error', {}, io.BytesIO(b'{"error":{"code":"KNOWN"}}'))
            with mock.patch.dict(os.environ, CONFIG), mock.patch.object(MODULE, 'urlopen', side_effect=failure):
                self.assertEqual(MODULE.forward_bingo('GET', '/bingo/health', None)[0], code)
        for failure in [URLError('private-fixture'), TimeoutError('private-fixture')]:
            with mock.patch.dict(os.environ, CONFIG), mock.patch.object(MODULE, 'urlopen', side_effect=failure):
                status, body = MODULE.forward_bingo('GET', '/bingo/health', None)
                self.assertEqual(status, 504)
                self.assertNotIn('private-fixture', json.dumps(body))
        with mock.patch.dict(os.environ, CONFIG), mock.patch.object(MODULE, 'urlopen', return_value=FakeResponse(b'invalid')):
            self.assertEqual(MODULE.forward_bingo('GET', '/bingo/health', None)[0], 502)


class HttpGatewayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), MODULE.VisionHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def call(self, path, body=None, origin='http://localhost:8110', host=None):
        headers = {'Origin': origin, 'Content-Type': 'application/json'}
        if host:
            headers['Host'] = host
        request = Request(self.base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        try:
            return urlopen(request, timeout=3)
        except HTTPError as error:
            return error

    def test_local_origin_and_credentials_not_in_browser_response(self):
        with mock.patch.object(MODULE, 'forward_bingo', return_value=(200, {'school': {'name': 'Real'}})) as forward:
            with self.call('/bingo/context') as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://localhost:8110')
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
                self.assertEqual(json.load(response), {'school': {'name': 'Real'}})
            forward.assert_called_once_with('GET', '/bingo/context', None)

    def test_remote_origin_and_dns_rebinding_host_rejected(self):
        with mock.patch.object(MODULE, 'forward_bingo') as forward:
            with self.call('/bingo/context', origin='https://evil.test') as response:
                self.assertEqual(response.status, 403)
                self.assertIsNone(response.headers.get('Access-Control-Allow-Origin'))
            with self.call('/bingo/context', host='evil.test') as response:
                self.assertEqual(response.status, 403)
            forward.assert_not_called()

    def test_browser_cannot_forge_identity_or_economics(self):
        with mock.patch.object(MODULE, 'forward_bingo') as forward:
            for body in [{'student_id': 'student', 'school_id': 'forged'}, {'event_id': 'event', 'points': 999}]:
                with self.call('/bingo/student-summary' if 'student_id' in body else '/bingo/deposits', body) as response:
                    self.assertEqual(response.status, 422)
            with self.call('/bingo/context?school_id=forged') as response:
                self.assertEqual(response.status, 404)
            forward.assert_not_called()

    def test_vision_route_still_uses_original_cascade(self):
        result = {'status': 'recognized', 'itemId': 'battery', 'origin': 'AWS_REKOGNITION'}
        request = Request(self.base + '/vision/analyze', data=b'image-fixture', headers={'Content-Type': 'image/png', 'Origin': 'http://localhost:8110'})
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(MODULE, 'analyze_primary_with_fallback', return_value=result) as cascade:
            with urlopen(request) as response:
                self.assertEqual(json.load(response), result)
            cascade.assert_called_once_with(b'image-fixture', 'image/png')


if __name__ == '__main__':
    unittest.main()
